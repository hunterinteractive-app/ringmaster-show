-- Preserve submitted entries while collecting their unpaid cart balance.
create schema if not exists checkout_private;
revoke all on schema checkout_private from public;

create or replace function checkout_private.submitted_entries(p_cart_id uuid)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(e) - array['updated_at','payment_status','paid_at','payment_session_id'] order by e.id),'[]'::jsonb)
 from public.entries e where e.source_cart_id=p_cart_id
$$;
revoke all on function checkout_private.submitted_entries(uuid) from public,anon,authenticated;

-- Scratch exemptions use the recorded timestamp and the show's entry deadline.
create or replace function checkout_private.scratch_exempt(p_entry public.entries)
returns boolean language sql stable set search_path='' as $$
 select coalesce(p_entry.scratched_at <= s.entry_close_at,false)
 from public.shows s where s.id=p_entry.show_id
$$;
revoke all on function checkout_private.scratch_exempt(public.entries) from public,anon,authenticated;

-- Only the locked submitted-balance checkout uses the filtered pricing input.
-- Keep original cart items and entries intact for audit and snapshot validation.
create or replace function checkout_private.pricing_items(p_cart_id uuid)
returns setof public.entry_cart_items language sql stable set search_path='' as $$
 select i.* from public.entry_cart_items i where i.cart_id=p_cart_id
 and not (coalesce(current_setting('ringmaster.checkout_reprice',true),'')='on'
   and exists(select 1 from public.entry_carts c where c.id=p_cart_id and c.status='submitted')
   and exists(select 1 from public.entries e where e.source_cart_id=p_cart_id
     and e.source_cart_item_id=i.id and checkout_private.scratch_exempt(e)))
$$;
revoke all on function checkout_private.pricing_items(uuid) from public,anon,authenticated;

create or replace function checkout_private.validate_submitted_cart(p_cart_id uuid)
returns void language plpgsql set search_path='' as $$
begin
 -- Known pre-deadline scratches are exempt; ambiguous changes still require review.
 if not exists(select 1 from public.entries where source_cart_id=p_cart_id)
 or exists(select 1 from public.entries e where e.source_cart_id=p_cart_id and
   ((not coalesce(checkout_private.scratch_exempt(e),false) and
     (e.scratched_at is not null or lower(coalesce(e.status,'')) in ('scratched','cancelled','canceled','deleted')))
    or not exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart_id
      and i.id=e.source_cart_item_id and i.exhibitor_id=e.exhibitor_id
      and i.section_id=e.section_id and i.animal_id is not distinct from e.animal_id
      and lower(trim(i.breed))=lower(trim(e.breed))
      and lower(trim(coalesce(i.variety,'')))=lower(trim(coalesce(e.variety,'')))
      and i.tattoo is not distinct from e.tattoo
      and coalesce(i.is_fur,false)=coalesce(e.is_fur,false)
      and (coalesce(i.is_fur,false) or (i.sex is not distinct from e.sex and i.class_name is not distinct from e.class_name)))))
 or exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart_id and
   (i.is_show_addon_carrier or (select count(*) from public.entries e
      where e.source_cart_id=p_cart_id and e.source_cart_item_id=i.id)<>1))
 or exists(select 1 from public.show_exhibitor_balances b where b.show_id=(select show_id from public.entry_carts where id=p_cart_id)
   and b.exhibitor_id in(select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id)
   and (b.paid_online_cents<>0 or b.paid_manual_cents<>0 or b.refunded_cents<>0)) then
   raise exception 'This submission has changes or prior payments. Please contact the show secretary to confirm the remaining balance.';
 end if;
end;
$$;
revoke all on function checkout_private.validate_submitted_cart(uuid) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.create_payment_quote_attempt(p_cart_id uuid, p_user_id uuid, p_provider text, p_platform_fee_default_percent numeric DEFAULT 0.02, p_processing_fee_percent numeric DEFAULT 0.029, p_processing_fee_fixed_cents integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cart public.entry_carts%rowtype;
  v_show public.shows%rowtype;
  v_active public.show_payment_sessions%rowtype;
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_enabled boolean := false;
  v_ready boolean := false;
  v_currency text;
  v_show_total integer;
  v_online_fee integer := 0;
  v_total integer;
  v_platform_fee integer;
  v_platform_raw numeric;
  v_platform_rate numeric;
  v_processing_rate numeric;
  v_combined_rate numeric;
  v_required_fee integer;
  v_snapshot jsonb;
  v_quote_hash text;
  v_idempotency_key text;
  v_attempt_number integer;
  v_session_id uuid;
  v_now timestamptz := now();
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  if v_provider not in ('stripe', 'square', 'paypal') then
    raise exception 'Unsupported payment provider';
  end if;

  select * into v_cart
  from public.entry_carts
  where id = p_cart_id
  for update;

  if not found then
    raise exception 'Cart not found';
  end if;
  if not household_private.has_access(v_cart.user_id, p_user_id) then
    raise exception 'You do not have access to this cart' using errcode = '42501';
  end if;
  if v_cart.status not in ('active', 'submitted') then
    raise exception 'Only active carts can be checked out';
  end if;
  if v_cart.status='submitted' then
    perform 1 from public.entries where source_cart_id=p_cart_id order by id for update;
    perform checkout_private.validate_submitted_cart(p_cart_id);
  end if;
  if v_cart.payment_status = 'paid' then
    raise exception 'Cart is already paid';
  end if;

  if v_cart.active_payment_session_id is not null then
    select * into v_active
    from public.show_payment_sessions
    where id = v_cart.active_payment_session_id
    for update;

    if found
       and v_active.provider = v_provider
       and v_active.attempt_status in ('created', 'pending', 'processing')
       and v_active.expires_at is not null
       and v_active.expires_at <= v_now then
      update public.show_payment_sessions
      set attempt_status = 'expired', status = 'expired',
          failure_code = 'expired',
          failure_message = 'The checkout attempt expired.', updated_at = v_now
      where id = v_active.id;
      update public.show_payments
      set status = 'cancelled', payment_status = 'cancelled', updated_at = v_now
      where payment_session_id = v_active.id
        and status not in ('paid', 'partially_refunded', 'refunded');
      update public.entry_carts
      set active_payment_session_id = null, payment_status = 'cancelled',
          updated_at = v_now
      where id = p_cart_id and active_payment_session_id = v_active.id;
    end if;

    if found
       and v_active.provider <> v_provider
       and v_active.attempt_status in ('created', 'pending', 'processing') then
      raise exception 'Another online payment attempt is already active';
    end if;
  end if;

  select * into v_show
  from public.shows
  where id = v_cart.show_id;

  if not found then
    raise exception 'Show not found';
  end if;
  if v_cart.status='active' and v_show.entry_close_at is not null and v_now > v_show.entry_close_at and exists (select 1 from public.entry_cart_items where cart_id=p_cart_id and not is_show_addon_carrier) then
    raise exception 'This show''s entry deadline has passed';
  end if;
  if v_show.payment_timing_mode not in ('online_only', 'online_or_at_show') then
    raise exception 'This show does not allow online payment';
  end if;
  if not exists (
    select 1 from public.entry_cart_items where cart_id = p_cart_id
  ) then
    raise exception 'Cart is empty';
  end if;
  if exists (
    select 1 from public.entry_cart_items
    where cart_id = p_cart_id and exhibitor_id is null
  ) then
    raise exception 'One or more cart items are missing an exhibitor assignment';
  end if;

  select
    case v_provider
      when 'stripe' then coalesce(ps.stripe_enabled, false)
      when 'square' then coalesce(ps.square_enabled, false)
      when 'paypal' then coalesce(ps.paypal_enabled, false)
    end
  into v_enabled
  from public.show_payment_settings ps
  where ps.show_id = v_show.id;

  if v_provider = 'stripe' then
    select exists (
      select 1 from public.show_payment_account_links l
      where l.show_id = v_show.id
        and l.provider = 'stripe'
        and l.stripe_account_id is not null
        and coalesce(l.charges_enabled, false)
        and coalesce(l.account_status, '') = 'ready'
    ) into v_ready;
  elsif v_provider = 'square' then
    select exists (
      select 1 from public.show_payment_account_links l
      where l.show_id = v_show.id
        and l.provider = 'square'
        and l.provider_account_id is not null
        and l.provider_location_id is not null
        and coalesce(l.status, '') in ('ready', 'connected', 'active')
    ) into v_ready;
  else
    select exists (
      select 1 from public.show_payment_account_links l
      where l.show_id = v_show.id
        and l.provider = 'paypal'
        and l.provider_account_id is not null
        and coalesce(l.status, '') in ('ready', 'connected', 'active')
    ) into v_ready;
  end if;

  if not coalesce(v_enabled, false) then
    raise exception 'The selected online payment provider is not enabled';
  end if;
  if not coalesce(v_ready, false) then
    raise exception 'The selected online payment provider is not ready';
  end if;

  -- Exactly one authoritative calculation occurs before the attempt begins.
  perform show_addons_private.validate_cart(p_cart_id);

  -- The ordinary calculator preserves pending balances. Only this authorized,
  -- cart-locked checkout path may refresh unpaid balances before making a quote.
  if exists(select 1 from public.show_exhibitor_balances where entry_cart_id=p_cart_id
    and source='cart' and (paid_online_cents<>0 or paid_manual_cents<>0 or refunded_cents<>0)) then
    raise exception 'This cart already has a payment. Please contact support before checking out again.';
  end if;
  -- Fee preparation also distinguishes pending from editable carts. The row
  -- remains locked; no other transaction can observe this temporary state.
  update public.entry_carts set active_payment_session_id=null, payment_status='unpaid'
    where id=p_cart_id;
  perform set_config('ringmaster.checkout_reprice', 'on', true);
  if v_cart.status='submitted' then
    update public.show_exhibitor_balances set entry_count=0,fur_count=0,
      entries_subtotal_cents=0,fur_subtotal_cents=0,show_fee_subtotal_cents=0,
      subtotal_before_discount_cents=0,discount_cents=0,calculated_total_cents=0,
      balance_due_cents=0,section_breakdown='[]'::jsonb,fee_snapshot='{}'::jsonb
    where entry_cart_id=p_cart_id and source='cart';
  end if;
  perform public.calculate_entry_cart_balance(p_cart_id);
  perform set_config('ringmaster.checkout_reprice', 'off', true);
  update public.entry_carts set active_payment_session_id=v_cart.active_payment_session_id,
    payment_status=v_cart.payment_status where id=p_cart_id;


  select
    min(lower(currency)),
    sum(balance_due_cents)::integer
  into v_currency, v_show_total
  from public.show_exhibitor_balances
  where entry_cart_id = p_cart_id and source = 'cart' and exhibitor_id in (select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id);

  if v_show_total is null or v_show_total <= 0 then
    raise exception 'Calculated checkout total must be greater than zero';
  end if;
  if exists (
    select 1 from public.show_exhibitor_balances
    where entry_cart_id = p_cart_id
      and source = 'cart'
      and lower(currency) <> v_currency
  ) then
    raise exception 'Cart contains mixed currencies';
  end if;
  if char_length(v_currency) <> 3 then
    raise exception 'Invalid checkout currency';
  end if;

  v_platform_raw := coalesce(v_show.platform_fee_percent,
    p_platform_fee_default_percent, 0.02);
  v_platform_rate := case
    when v_platform_raw > 1 then v_platform_raw / 100.0
    else v_platform_raw
  end;
  v_processing_rate := case
    when coalesce(p_processing_fee_percent, 0) > 1
      then p_processing_fee_percent / 100.0
    else coalesce(p_processing_fee_percent, 0)
  end;

  if v_platform_rate < 0 or v_processing_rate < 0 then
    raise exception 'Fee percentages cannot be negative';
  end if;
  v_combined_rate := v_platform_rate + v_processing_rate;
  if v_combined_rate >= 1 then
    raise exception 'Configured fee percentages are too high';
  end if;

  if v_show.online_payment_fee_mode = 'pass_to_exhibitor' then
    v_online_fee := greatest(ceil(
      (v_show_total + greatest(coalesce(p_processing_fee_fixed_cents, 0), 0))
      / (1 - v_combined_rate) - v_show_total
    )::integer, 0);

    for i in 1..10 loop
      v_total := v_show_total + v_online_fee;
      v_required_fee := round(v_total * v_platform_rate)::integer
        + ceil(v_total * v_processing_rate
          + greatest(coalesce(p_processing_fee_fixed_cents, 0), 0))::integer;
      exit when v_online_fee >= v_required_fee;
      v_online_fee := v_required_fee;
    end loop;
  end if;

  v_total := v_show_total + v_online_fee;
  v_platform_fee := round(v_total * v_platform_rate)::integer;
  if v_platform_fee < 1 and v_platform_rate > 0 then
    v_platform_fee := 1;
  end if;
  if v_platform_fee >= v_total then
    raise exception 'Platform fee must be less than the charged amount';
  end if;

  select jsonb_build_object(
    'version', 1,
    'cart_id', p_cart_id,
    'show_id', v_show.id,
    'show_name', v_show.name,
    'user_id', p_user_id,
    'provider', v_provider,
    'currency', v_currency,
    'show_balance_total_cents', v_show_total,
    'online_fee_cents', v_online_fee,
    'platform_fee_cents', v_platform_fee,
    'expected_amount_cents', v_total,
    'platform_fee_rate', v_platform_rate,
    'processing_fee_rate', v_processing_rate,
    'processing_fee_fixed_cents', greatest(coalesce(p_processing_fee_fixed_cents, 0), 0),
    'online_payment_fee_mode', v_show.online_payment_fee_mode,
    'online_payment_fee_label', v_show.online_payment_fee_label,
    'online_payment_fee_description', v_show.online_payment_fee_description,
    'balances', coalesce(jsonb_agg(jsonb_build_object(
      'balance_id', b.id,
      'exhibitor_id', b.exhibitor_id,
      'exhibitor_user_id', b.exhibitor_user_id,
      'entry_count', b.entry_count,
      'fur_count', b.fur_count,
      'entries_subtotal_cents', b.entries_subtotal_cents,
      'fur_subtotal_cents', b.fur_subtotal_cents,
      'show_fee_subtotal_cents', b.show_fee_subtotal_cents,
      'subtotal_before_discount_cents', b.subtotal_before_discount_cents,
      'discount_cents', b.discount_cents,
      'amount_cents', b.balance_due_cents,
      'fee_snapshot', b.fee_snapshot,
      'section_breakdown', b.section_breakdown
    ) order by b.id), '[]'::jsonb)
  ) into v_snapshot
  from public.show_exhibitor_balances b
  where b.entry_cart_id = p_cart_id and b.source = 'cart' and b.exhibitor_id in (select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id);

  v_snapshot := v_snapshot || jsonb_build_object('cart_items', checkout_private.cart_items(p_cart_id));
  if v_cart.status='submitted' then
    v_snapshot := v_snapshot || jsonb_build_object('settles_submitted_entries',true,'submitted_entries',checkout_private.submitted_entries(p_cart_id));
  end if;
  v_quote_hash := encode(
    extensions.digest(convert_to(v_snapshot::text, 'UTF8'), 'sha256'),
    'hex'
  );
    if v_active.id is not null
       and v_active.quote_hash = v_quote_hash and v_active.quote_snapshot = v_snapshot
       and v_active.provider = v_provider
       and v_active.attempt_status in ('created', 'pending', 'processing')
       and (v_active.expires_at is null or v_active.expires_at > v_now) then
      return jsonb_build_object(
        'reused', true,
        'payment_session_id', v_active.id,
        'idempotency_key', v_active.idempotency_key,
        'quote_hash', v_active.quote_hash,
        'quote', v_active.quote_snapshot,
        'provider_session_id', v_active.provider_session_id,
        'checkout_url', v_active.checkout_url,
        'expires_at', v_active.expires_at
      );
    end if;


  select count(*) + 1 into v_attempt_number
  from public.show_payment_sessions
  where cart_id = p_cart_id and provider = v_provider;
  v_idempotency_key := format(
    'cart:%s:%s:%s:v%s', p_cart_id, v_provider, v_quote_hash, v_attempt_number
  );

  update public.show_payment_sessions
  set
    attempt_status = 'superseded',
    status = 'expired',
    failure_code = 'superseded',
    failure_message = 'A newer checkout attempt replaced this attempt.',
    updated_at = v_now
  where cart_id = p_cart_id
    and provider = v_provider
    and attempt_status in ('created', 'pending', 'processing');


  update public.show_payments set status='cancelled', payment_status='cancelled', updated_at=v_now
  where cart_id=p_cart_id and payment_session_id in
    (select id from public.show_payment_sessions where cart_id=p_cart_id and attempt_status='superseded')
    and status in ('pending','processing','requires_action');

  insert into public.show_payment_sessions (
    show_id, cart_id, provider, status, currency, amount_cents,
    platform_fee_cents, online_fee_cents, metadata, idempotency_key,
    quote_hash, quote_version, attempt_status, expected_amount_cents,
    expected_currency, quote_snapshot, created_at, updated_at
  ) values (
    v_show.id, p_cart_id, v_provider, 'created', v_currency, v_total,
    v_platform_fee, v_online_fee,
    jsonb_build_object('source', 'provider_neutral_checkout'),
    v_idempotency_key, v_quote_hash, 1, 'created', v_total, v_currency,
    v_snapshot, v_now, v_now
  ) returning id into v_session_id;

  with balances as (
    select
      b.*,
      row_number() over (order by b.id) as rn,
      count(*) over () as row_count,
      floor(b.balance_due_cents::numeric * v_platform_fee / v_show_total)::integer
        as platform_base,
      floor(b.balance_due_cents::numeric * v_online_fee / v_show_total)::integer
        as online_base
    from public.show_exhibitor_balances b
    where b.entry_cart_id = p_cart_id and b.source = 'cart' and b.exhibitor_id in (select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id)
  ), allocated as (
    select balances.*,
      platform_base + case when rn = row_count then
        v_platform_fee - sum(platform_base) over () else 0 end
        as allocated_platform_fee,
      online_base + case when rn = row_count then
        v_online_fee - sum(online_base) over () else 0 end
        as allocated_online_fee
    from balances
  )
  insert into public.show_payments (
    show_id, exhibitor_user_id, exhibitor_id, entry_cart_id, cart_id,
    currency, subtotal_cents, total_cents, platform_fee_cents, status,
    payment_method, provider, payment_type, amount_cents,
    platform_fee_percent, platform_fee_amount_cents, payer_user_id,
    payment_method_type, balance_id, metadata, payment_status,
    payment_session_id, gross_charged_cents, online_fee_cents,
    refunded_cents, application_fee_refunded_cents, created_at, updated_at
  )
  select
    v_show.id, a.exhibitor_user_id, a.exhibitor_id, p_cart_id, p_cart_id,
    v_currency, a.subtotal_before_discount_cents, a.balance_due_cents,
    a.allocated_platform_fee, 'pending', v_provider, v_provider, 'checkout',
    a.balance_due_cents, v_platform_rate * 100,
    a.allocated_platform_fee, p_user_id, 'card', a.id,
    jsonb_build_object(
      'quote_hash', v_quote_hash,
      'payment_session_id', v_session_id,
      'allocated_online_fee_cents', a.allocated_online_fee,
      'fee_snapshot', a.fee_snapshot,
      'section_breakdown', a.section_breakdown
    ),
    'pending', v_session_id,
    a.balance_due_cents + a.allocated_online_fee,
    a.allocated_online_fee, 0, 0, v_now, v_now
  from allocated a;

  insert into public.show_payment_line_items (
    show_payment_id, payment_session_id, cart_id, exhibitor_id, balance_id,
    item_type, line_type, label, quantity, unit_amount_cents,
    total_amount_cents, metadata
  )
  select null, v_session_id, p_cart_id, b.exhibitor_id, b.id,
    case when x.line_type = 'entry_fee' then 'entry_fee' else 'other' end,
    x.line_type, x.label, 1, x.amount, x.amount,
    jsonb_build_object('quote_hash', v_quote_hash)
  from public.show_exhibitor_balances b
  cross join lateral (values
    ('entry_fee', 'Entry fees', b.entries_subtotal_cents),
    ('fur_fee', 'Fur / Wool fees', b.fur_subtotal_cents),
    ('per_show_fee', 'Per-show fees', b.show_fee_subtotal_cents-coalesce((b.fee_snapshot->>'exhibitor_fee_cents')::integer,0)),
    ('per_show_fee', coalesce(b.fee_snapshot->>'exhibitor_fee_label','Exhibitor Fee'), coalesce((b.fee_snapshot->>'exhibitor_fee_cents')::integer,0)),
    ('discount', 'Discount', -b.discount_cents)
  ) as x(line_type, label, amount)
  where b.entry_cart_id = p_cart_id
    and b.source = 'cart'
    and x.amount <> 0;

  insert into public.show_payment_line_items(payment_session_id,cart_id,exhibitor_id,balance_id,item_type,line_type,label,quantity,unit_amount_cents,total_amount_cents,metadata)
  select v_session_id,p_cart_id,r.exhibitor_id,b.id,'other','adjustment',r.name,r.quantity,r.unit_price_cents,r.quantity*r.unit_price_cents,
    jsonb_build_object('show_addon_id',r.id,'kind',r.kind,'quote_hash',v_quote_hash)
  from show_addons_private.selections r join public.show_exhibitor_balances b on b.entry_cart_id=r.cart_id and b.exhibitor_id=r.exhibitor_id and b.source='cart' where r.cart_id=p_cart_id;

  if v_online_fee <> 0 then
    insert into public.show_payment_line_items (
      show_payment_id, payment_session_id, cart_id, item_type, line_type,
      label, quantity, unit_amount_cents, total_amount_cents, metadata
    ) values (
      null, v_session_id, p_cart_id, 'other', 'online_fee',
      v_show.online_payment_fee_label, 1, v_online_fee, v_online_fee,
      jsonb_build_object('quote_hash', v_quote_hash)
    );
  end if;

  insert into public.show_payment_line_items (
    show_payment_id, payment_session_id, cart_id, item_type, line_type,
    label, quantity, unit_amount_cents, total_amount_cents, metadata
  ) values (
    null, v_session_id, p_cart_id, 'other', 'platform_fee',
    'Platform fee', 1, v_platform_fee, v_platform_fee,
    jsonb_build_object('included_in_online_fee',
      v_show.online_payment_fee_mode = 'pass_to_exhibitor')
  );

  update public.entry_carts
  set
    active_payment_session_id = v_session_id,
    selected_payment_timing = 'online',
    selected_payment_provider = v_provider,
    payment_provider = v_provider,
    payment_status = 'pending',
    payment_attempt_started_at = v_now,
    payment_amount_total = v_total::numeric / 100,
    payment_currency = v_currency,
    updated_at = v_now
  where id = p_cart_id;

  return jsonb_build_object(
    'reused', false,
    'payment_session_id', v_session_id,
    'idempotency_key', v_idempotency_key,
    'quote_hash', v_quote_hash,
    'quote', v_snapshot
  );
end;
$function$;
;
CREATE OR REPLACE FUNCTION public.finalize_entry_cart_paid(p_cart_id uuid, p_payment_session_id uuid, p_provider text, p_provider_payment_id text, p_amount_cents integer, p_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cart public.entry_carts%rowtype;
  v_session public.show_payment_sessions%rowtype;
  v_provider text := lower(btrim(coalesce(p_provider, '')));
  v_currency text := lower(btrim(coalesce(p_currency, '')));
  v_payment record;
  v_payment_count integer;
  v_pending_count integer;
  v_added integer;
  v_entries_created integer := 0;
  v_result jsonb;
  v_now timestamptz := now();
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;

  select * into v_cart
  from public.entry_carts
  where id = p_cart_id
  for update;

  if not found then
    raise exception 'Cart not found';
  end if;

  select * into v_session
  from public.show_payment_sessions
  where id = p_payment_session_id
  for update;

  if not found or v_session.cart_id is distinct from p_cart_id then
    raise exception 'Payment session does not belong to this cart';
  end if;
  if v_session.provider <> v_provider then
    raise exception 'Payment provider does not match the attempt';
  end if;

  if v_session.attempt_status = 'finalized' then
    return coalesce(
      v_session.metadata -> 'finalization_result',
      jsonb_build_object(
        'finalized', true,
        'already_finalized', true,
        'entries_created', (
          select count(*) from public.entries
          where payment_session_id = p_payment_session_id
        ),
        'payment_session_id', p_payment_session_id
      )
    ) || jsonb_build_object('already_finalized', true);
  end if;

  if v_session.attempt_status in ('failed', 'cancelled', 'expired', 'superseded') then
    raise exception 'Payment attempt cannot be finalized from status %',
      v_session.attempt_status;
  end if;
  if v_cart.active_payment_session_id is distinct from p_payment_session_id then
    raise exception 'This payment attempt is no longer active';
  end if;

  -- Old quotes lack item identity and must be reviewed rather than silently
  -- attaching unpurchased items. The durable payment queue retains failures.
  if v_session.quote_snapshot->'cart_items' is distinct from checkout_private.cart_items(p_cart_id) then
    raise exception 'Cart changed after checkout was calculated. Refresh checkout before paying. If already charged, contact support; do not pay again.';
  end if;
  if coalesce((v_session.quote_snapshot->>'settles_submitted_entries')::boolean,false) then
    perform 1 from public.entries where source_cart_id=p_cart_id order by id for update;
    perform checkout_private.validate_submitted_cart(p_cart_id);
    if v_cart.status<>'submitted' or v_session.quote_snapshot->'submitted_entries'
       is distinct from checkout_private.submitted_entries(p_cart_id) then
      raise exception 'Submitted entries changed after checkout. Contact support; do not pay again.';
    end if;
  end if;
  if p_amount_cents is distinct from v_session.expected_amount_cents then
    raise exception 'Charged amount does not match the saved quote';
  end if;
  if v_currency is distinct from lower(v_session.expected_currency) then
    raise exception 'Charged currency does not match the saved quote';
  end if;
  if nullif(btrim(coalesce(p_provider_payment_id, '')), '') is null then
    raise exception 'Provider payment ID is required';
  end if;
  if v_session.provider_payment_id is not null
     and v_session.provider_payment_id <> p_provider_payment_id then
    raise exception 'Provider payment ID does not match the attempt';
  end if;

  -- Acquire ledger locks in a consistent order before any writes.
  perform 1
  from public.show_payments
  where payment_session_id = p_payment_session_id and provider = v_provider
  order by id
  for update;

  select
    count(*),
    count(*) filter (where status in ('pending', 'processing', 'requires_action'))
  into v_payment_count, v_pending_count
  from public.show_payments
  where payment_session_id = p_payment_session_id and provider = v_provider;

  if v_payment_count = 0 then
    raise exception 'No matching payment ledger rows exist';
  end if;
  if v_pending_count <> v_payment_count then
    raise exception 'Payment ledger rows are not all pending';
  end if;

  update public.show_payments
  set
    status = 'paid',
    payment_status = 'paid',
    provider_payment_id = p_provider_payment_id,
    payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else payment_intent_id end,
    stripe_payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else stripe_payment_intent_id end,
    paid_at = v_now,
    updated_at = v_now
  where payment_session_id = p_payment_session_id and provider = v_provider;

  -- Refresh the balance snapshot before applying the successful payment.
  -- calculate_entry_cart_balance_internal initializes the balance as unpaid;
  -- apply_show_payment_to_balance below then applies the payment correctly.
  if not coalesce((v_session.quote_snapshot->>'settles_submitted_entries')::boolean,false) then
    perform public.calculate_entry_cart_balance_internal(p_cart_id);
  end if;

  perform set_config('ringmaster.payment_state_write', 'on', true);
  for v_payment in
    select id from public.show_payments
    where payment_session_id = p_payment_session_id and provider = v_provider
    order by id
  loop
    perform public.apply_show_payment_to_balance(v_payment.id);
  end loop;
  perform set_config('ringmaster.payment_state_write', 'off', true);

  if coalesce((v_session.quote_snapshot->>'settles_submitted_entries')::boolean,false) then
    update public.entries set payment_status='paid', paid_at=v_now,
      payment_session_id=p_payment_session_id where source_cart_id=p_cart_id
      and not coalesce(checkout_private.scratch_exempt(entries),false);
  else
  insert into public.entries (
    show_id, exhibitor_id, animal_id, species, tattoo, animal_name, breed,
    variety, fur_variety, sex, class_name, status, section_id,
    exhibitor_user_id, created_at, is_fur, payment_status, paid_at,
    source_cart_id, source_cart_item_id, payment_session_id, cart_entry_kind
  )
  select
    v_cart.show_id, i.exhibitor_id, i.animal_id, i.species, i.tattoo,
    coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed, i.variety,
    null, i.sex, i.class_name, 'entered', i.section_id, v_cart.user_id,
    v_now, false, 'paid', v_now, p_cart_id, i.id,
    p_payment_session_id, 'entry'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id and not i.is_show_addon_carrier and not coalesce(i.is_fur, false)
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_entries_created := v_entries_created + v_added;

  insert into public.entries (
    show_id, exhibitor_id, animal_id, species, tattoo, animal_name, breed,
    variety, fur_variety, sex, class_name, status, section_id,
    exhibitor_user_id, created_at, is_fur, payment_status, paid_at,
    source_cart_id, source_cart_item_id, payment_session_id, cart_entry_kind
  )
  select
    v_cart.show_id, i.exhibitor_id, i.animal_id, i.species, i.tattoo,
    coalesce(nullif(btrim(i.animal_name), ''), i.tattoo), i.breed, i.variety,
    coalesce(
      nullif(btrim(i.fur_variety), ''),
      case when lower(coalesce(i.variety, '')) in (
        'white', 'blue eyed white', 'blue-eyed white', 'bew',
        'ruby eyed white', 'ruby-eyed white', 'rew'
      ) then 'White' else 'Colored' end
    ),
    null, 'Fur / Wool', 'entered', i.section_id, v_cart.user_id,
    v_now, true, 'paid', v_now, p_cart_id, i.id,
    p_payment_session_id, 'fur'
  from public.entry_cart_items i
  where i.cart_id = p_cart_id and not i.is_show_addon_carrier and coalesce(i.is_fur, false)
  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)
    where source_cart_id is not null
      and source_cart_item_id is not null
      and cart_entry_kind is not null
  do nothing;
  get diagnostics v_added = row_count;
  v_entries_created := v_entries_created + v_added;

  end if;

  update public.entry_carts
  set
    status = 'submitted',
    submitted_at = coalesce(submitted_at, v_now),
    payment_status = 'paid',
    payment_provider = v_provider,
    selected_payment_timing = 'online',
    selected_payment_provider = v_provider,
    completed_payment_session_id = p_payment_session_id,
    provider_payment_id = p_provider_payment_id,
    payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else payment_intent_id end,
    checkout_session_id = coalesce(v_session.provider_session_id,
      checkout_session_id),
    payment_amount_total = p_amount_cents::numeric / 100,
    payment_currency = v_currency,
    paid_at = v_now,
    payment_finalized_at = v_now,
    updated_at = v_now
  where id = p_cart_id;

  v_result := jsonb_build_object(
    'finalized', true,
    'already_finalized', false,
    'entries_created', v_entries_created,
    'payment_session_id', p_payment_session_id
  );

  update public.show_payment_sessions
  set
    provider_payment_id = p_provider_payment_id,
    stripe_payment_intent_id = case when v_provider = 'stripe'
      then p_provider_payment_id else stripe_payment_intent_id end,
    attempt_status = 'finalized',
    status = 'paid',
    finalized_at = v_now,
    metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object('finalization_result', v_result),
    updated_at = v_now
  where id = p_payment_session_id;

  return v_result;
end;
$function$;
;

create or replace function checkout_private.submitted_cart_needs_review(p_cart_id uuid)
returns boolean language plpgsql set search_path='' as $$
begin
 perform checkout_private.validate_submitted_cart(p_cart_id);
 return false;
exception when raise_exception then return true;
end;
$$;
revoke all on function checkout_private.submitted_cart_needs_review(uuid) from public,anon,authenticated;

-- The UI can see only submissions belonging to its authenticated household.
create or replace function checkout_private.list_submitted_balances(p_show_id uuid)
returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(row_to_json(r) order by r.submitted_at),'[]'::jsonb) from (
 select c.id cart_id,c.submitted_at,min(b.currency) currency,
        checkout_private.submitted_cart_needs_review(c.id) review_required,
        sum(b.balance_due_cents) balance_due_cents,
        string_agg(distinct e.display_name, ', ' order by e.display_name) exhibitors,
        s.payment_timing_mode in ('online_only','online_or_at_show') and coalesce(ps.stripe_enabled,false)
        and exists(select 1 from public.show_payment_account_links l where l.show_id=s.id
          and l.provider='stripe' and l.charges_enabled and l.account_status='ready') online_available
 from public.entry_carts c join public.shows s on s.id=c.show_id
 join public.show_exhibitor_balances b on b.entry_cart_id=c.id and b.source='cart'
 join public.exhibitors e on e.id=b.exhibitor_id
 left join public.show_payment_settings ps on ps.show_id=s.id
 where auth.uid() is not null and household_private.has_access(c.user_id,auth.uid())
   and c.show_id=p_show_id and c.status='submitted' and c.payment_status<>'paid'
 group by c.id,s.id,ps.stripe_enabled having sum(b.balance_due_cents)>0
 ) r
$$;
revoke all on function checkout_private.list_submitted_balances(uuid) from public,anon;
grant usage on schema checkout_private to authenticated;
grant execute on function checkout_private.list_submitted_balances(uuid) to authenticated;
create or replace function public.list_my_submitted_balances(p_show_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
 select checkout_private.list_submitted_balances(p_show_id)
$$;
revoke all on function public.list_my_submitted_balances(uuid) from public,anon;
grant execute on function public.list_my_submitted_balances(uuid) to authenticated;
revoke all on function public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer) from public,anon,authenticated;
grant execute on function public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer) to service_role;
revoke all on function public.finalize_entry_cart_paid(uuid,uuid,text,text,integer,text) from public,anon,authenticated;
grant execute on function public.finalize_entry_cart_paid(uuid,uuid,text,text,integer,text) to service_role;

CREATE OR REPLACE FUNCTION public.calculate_entry_cart_balance_without_canada_special(p_cart_id uuid)
 RETURNS SETOF show_exhibitor_balances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_show_id uuid;
  v_cart_user_id uuid;

  v_currency text := 'usd';

  v_discount_enabled boolean := false;
  v_discount_type text := 'amount';
  v_discount_value numeric := 0;

  v_discount_basis text := 'each_show';
  v_discount_scope text := 'both';
  v_discount_min_entries integer := 0;
  v_discount_max_entries integer := null;
  v_discount_required_shows integer := 0;
begin
  select
    c.show_id,
    c.user_id
  into
    v_show_id,
    v_cart_user_id
  from public.entry_carts c
  where c.id = p_cart_id;

  if v_show_id is null then
    raise exception 'Cart % not found', p_cart_id;
  end if;

  select
    lower(coalesce(sfs.currency, 'usd')),
    coalesce(sfs.multi_show_discount_enabled, false),
    lower(coalesce(sfs.multi_show_discount_type, 'amount')),
    coalesce(sfs.multi_show_discount_value, 0),
    lower(coalesce(sfs.multi_show_discount_basis, 'each_show')),
    lower(coalesce(sfs.multi_show_discount_scope, 'both')),
    coalesce(sfs.multi_show_discount_min_entries, 0),
    sfs.multi_show_discount_max_entries,
    coalesce(sfs.multi_show_discount_required_shows, 0)
  into
    v_currency,
    v_discount_enabled,
    v_discount_type,
    v_discount_value,
    v_discount_basis,
    v_discount_scope,
    v_discount_min_entries,
    v_discount_max_entries,
    v_discount_required_shows
  from public.show_fee_settings sfs
  where sfs.show_id = v_show_id;

  -- Apply safe defaults when the show has no fee-settings row.
  if not found then
    v_currency := 'usd';
    v_discount_enabled := false;
    v_discount_type := 'amount';
    v_discount_value := 0;
    v_discount_basis := 'each_show';
    v_discount_scope := 'both';
    v_discount_min_entries := 0;
    v_discount_max_entries := null;
    v_discount_required_shows := 0;
  end if;

  if length(v_currency) <> 3 then
    v_currency := 'usd';
  end if;

  if v_discount_type not in ('fixed_rate', 'amount', 'percent') then
    v_discount_type := 'amount';
  end if;

  if v_discount_basis not in ('each_show', 'cumulative') then
    v_discount_basis := 'each_show';
  end if;

  if v_discount_scope not in ('both', 'open', 'youth') then
    v_discount_scope := 'both';
  end if;

  v_discount_value := greatest(coalesce(v_discount_value, 0), 0);
  v_discount_min_entries :=
    greatest(coalesce(v_discount_min_entries, 0), 0);
  v_discount_required_shows :=
    greatest(coalesce(v_discount_required_shows, 0), 0);

  if v_discount_max_entries is not null then
    v_discount_max_entries :=
      greatest(v_discount_max_entries, 0);
  end if;

  if not exists (
    select 1
    from checkout_private.pricing_items(p_cart_id) eci
    where eci.cart_id = p_cart_id
  ) then
    raise exception 'Cart % is empty', p_cart_id;
  end if;

  if exists (
    select 1
    from checkout_private.pricing_items(p_cart_id) eci
    where eci.cart_id = p_cart_id
      and eci.exhibitor_id is null
  ) then
    raise exception
      'Cart % has one or more items missing exhibitor_id',
      p_cart_id;
  end if;

  perform exhibitor_fees_private.prepare_cart(p_cart_id);

  return query
  with cart_items as (
    select
      eci.id,
      eci.cart_id,
      eci.section_id,
      eci.animal_id,
      eci.exhibitor_id,
      coalesce(eci.is_fur, false) as is_fur,
      eci.created_at,
      (coalesce(eci.is_exhibitor_fee_carrier, false) or eci.is_show_addon_carrier) as is_exhibitor_fee_carrier
    from checkout_private.pricing_items(p_cart_id) eci
    where eci.cart_id = p_cart_id
      and eci.exhibitor_id is not null
  ),

  priced_items as (
    select
      ci.*,
      ss.show_id,
      lower(ss.kind::text) as section_kind,
      ss.letter as section_letter,
      coalesce(
        nullif(btrim(ss.display_name), ''),
        concat(
          initcap(ss.kind::text),
          ' ',
          coalesce(ss.letter, '')
        )
      ) as section_label,
      ss.sort_order as section_sort_order,

      (case when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fee_per_entry, 0) end)::numeric
        as fee_per_entry,

      (case when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fee_per_show, 0) end)::numeric
        as fee_per_show,

      (case when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fur_fee, 0) end)::numeric
        as fur_fee,

      case
        when ci.is_exhibitor_fee_carrier then false
        when v_discount_scope = 'both' then true
        when lower(ss.kind::text) = v_discount_scope then true
        else false
      end as eligible_for_discount

    from cart_items ci

    join public.show_sections ss
      on ss.id = ci.section_id

    left join public.show_section_fee_settings sffs
      on sffs.section_id = ci.section_id

    where ss.show_id = v_show_id
  ),

  /*
   * All section totals remain included in the balance, regardless of whether
   * the section is eligible for the selected discount scope.
   */
  section_counts as (
    select
      pi.exhibitor_id,
      pi.section_id,

      min(pi.section_kind) as section_kind,
      min(pi.section_letter) as section_letter,
      min(pi.section_label) as section_label,

      min(
        coalesce(pi.section_sort_order, 999999)
      ) as section_sort_order,

      count(*) filter (where not pi.is_fur and not pi.is_exhibitor_fee_carrier)::integer as entry_count,

      count(*) filter (
        where pi.is_fur
      )::integer as fur_count,

      round(
        sum(case when not pi.is_fur then pi.fee_per_entry else 0 end) * 100
      )::integer as entries_subtotal_cents,

      round(
        sum(
          case
            when pi.is_fur then pi.fur_fee
            else 0
          end
        ) * 100
      )::integer as fur_subtotal_cents,

      round(
        max(pi.fee_per_show) * 100
      )::integer as show_fee_cents

    from priced_items pi

    group by
      pi.exhibitor_id,
      pi.section_id
  ),

  /*
   * Counts only sections permitted by multi_show_discount_scope.
   */
  eligible_section_counts as (
    select
      pi.exhibitor_id,
      pi.section_id,
      count(*) filter (where not pi.is_fur and not pi.is_exhibitor_fee_carrier)::integer as eligible_entry_count

    from priced_items pi

    where pi.eligible_for_discount = true
      and not pi.is_fur and not pi.is_exhibitor_fee_carrier

    group by
      pi.exhibitor_id,
      pi.section_id
  ),

  /*
   * Determines whether each exhibitor qualifies.
   *
   * each_show:
   *   At least the configured number of sections must each contain the
   *   configured minimum number of entries.
   *
   * cumulative:
   *   The exhibitor must enter at least the configured number of sections
   *   and have at least the configured total number of eligible entries.
   */
  exhibitor_discount_stats as (
    select
      pi.exhibitor_id,

      count(*) filter (
        where pi.eligible_for_discount
          and not pi.is_fur and not pi.is_exhibitor_fee_carrier
      )::integer as eligible_entry_count,

      count(
        distinct pi.section_id
      ) filter (
        where pi.eligible_for_discount
      )::integer as eligible_show_count,

      coalesce((
        select count(*)::integer
        from eligible_section_counts esc
        where esc.exhibitor_id = pi.exhibitor_id
          and esc.eligible_entry_count >= v_discount_min_entries
      ), 0) as qualifying_show_count

    from priced_items pi

    group by pi.exhibitor_id
  ),

  /*
   * Add deterministic numbering so an optional maximum can be applied.
   *
   * For cumulative discounts, maximum entries is applied across all eligible
   * entries for the exhibitor.
   *
   * For each-show discounts, maximum entries is applied separately to each
   * qualifying show section, matching the cart-screen calculation.
   */
  eligible_ranked_items as (
    select
      pi.*,

      row_number() over (
        partition by pi.exhibitor_id
        order by
          pi.created_at,
          pi.id
      ) as cumulative_entry_number,

      row_number() over (
        partition by
          pi.exhibitor_id,
          pi.section_id
        order by
          pi.created_at,
          pi.id
      ) as section_entry_number

    from priced_items pi

    where pi.eligible_for_discount = true
      and not pi.is_fur and not pi.is_exhibitor_fee_carrier
  ),

  discount_eligible_items as (
    select eri.*

    from eligible_ranked_items eri

    join exhibitor_discount_stats eds
      on eds.exhibitor_id = eri.exhibitor_id

    join eligible_section_counts esc
      on esc.exhibitor_id = eri.exhibitor_id
     and esc.section_id = eri.section_id

    where
      v_discount_enabled = true

      and v_discount_min_entries > 0

      and v_discount_required_shows > 0

      and (
        (
          v_discount_basis = 'cumulative'

          and eds.eligible_show_count
            >= v_discount_required_shows

          and eds.eligible_entry_count
            >= v_discount_min_entries

          and (
            v_discount_max_entries is null
            or eri.cumulative_entry_number
              <= v_discount_max_entries
          )
        )

        or

        (
          v_discount_basis = 'each_show'

          and eds.qualifying_show_count
            >= v_discount_required_shows

          and esc.eligible_entry_count
            >= v_discount_min_entries

          and (
            v_discount_max_entries is null
            or eri.section_entry_number
              <= v_discount_max_entries
          )
        )
      )
  ),

  /*
   * Calculate the discount one item at a time so differing section entry
   * fees are handled correctly.
   */
  exhibitor_discount_totals as (
    select
      dei.exhibitor_id,

      count(*)::integer as qualifying_entry_count,

      count(
        distinct dei.section_id
      )::integer as discounted_show_count,

      round(
        sum(
          least(
            dei.fee_per_entry,

            greatest(
              case
                when v_discount_type = 'fixed_rate' then
                  dei.fee_per_entry - v_discount_value

                when v_discount_type = 'percent' then
                  dei.fee_per_entry
                  *
                  case
                    when v_discount_value <= 1 then
                      v_discount_value
                    else
                      v_discount_value / 100.0
                  end

                when v_discount_type = 'amount' then
                  v_discount_value

                else 0
              end,
              0
            )
          )
        ) * 100
      )::integer as discount_cents

    from discount_eligible_items dei

    group by dei.exhibitor_id
  ),

  exhibitor_totals_raw as (
    select
      pi.exhibitor_id,

      count(*) filter (where not pi.is_fur and not pi.is_exhibitor_fee_carrier)::integer as entry_count,

      count(*) filter (
        where pi.is_fur
      )::integer as fur_count,

      round(
        sum(case when not pi.is_fur then pi.fee_per_entry else 0 end) * 100
      )::integer as entries_subtotal_cents,

      round(
        sum(
          case
            when pi.is_fur then pi.fur_fee
            else 0
          end
        ) * 100
      )::integer as fur_subtotal_cents,

      coalesce((
        select sum(sc.show_fee_cents)::integer
        from section_counts sc
        where sc.exhibitor_id = pi.exhibitor_id
      ), 0) as show_fee_subtotal_cents,

      coalesce(
        eds.eligible_entry_count,
        0
      )::integer as eligible_entry_count,

      coalesce(
        eds.eligible_show_count,
        0
      )::integer as eligible_show_count,

      coalesce(
        eds.qualifying_show_count,
        0
      )::integer as qualifying_show_count,

      coalesce(
        edt.qualifying_entry_count,
        0
      )::integer as qualifying_entry_count,

      coalesce(
        edt.discounted_show_count,
        0
      )::integer as discounted_show_count,

      greatest(
        coalesce(edt.discount_cents, 0),
        0
      )::integer as discount_cents

    from priced_items pi

    left join exhibitor_discount_stats eds
      on eds.exhibitor_id = pi.exhibitor_id

    left join exhibitor_discount_totals edt
      on edt.exhibitor_id = pi.exhibitor_id

    group by
      pi.exhibitor_id,
      eds.eligible_entry_count,
      eds.eligible_show_count,
      eds.qualifying_show_count,
      edt.qualifying_entry_count,
      edt.discounted_show_count,
      edt.discount_cents
  ),

  exhibitor_totals as (
    select
      etr.*,

      (
        etr.entries_subtotal_cents
        + etr.fur_subtotal_cents
        + etr.show_fee_subtotal_cents
      )::integer as subtotal_before_discount_cents

    from exhibitor_totals_raw etr
  ),

  final_rows as (
    select
      et.exhibitor_id,

      coalesce(
        ex.owner_user_id,
        v_cart_user_id
      ) as exhibitor_user_id,

      et.entry_count,
      et.fur_count,
      et.entries_subtotal_cents,
      et.fur_subtotal_cents,
      et.show_fee_subtotal_cents,
      et.subtotal_before_discount_cents,

      least(
        greatest(et.discount_cents, 0),
        et.entries_subtotal_cents
      )::integer as discount_cents,

      greatest(
        et.subtotal_before_discount_cents
        - least(
            greatest(et.discount_cents, 0),
            et.entries_subtotal_cents
          ),
        0
      )::integer as calculated_total_cents,

      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'section_id', sc.section_id,
            'kind', sc.section_kind,
            'letter', sc.section_letter,
            'label', sc.section_label,
            'entry_count', sc.entry_count,
            'fur_count', sc.fur_count,
            'entries_subtotal_cents',
              sc.entries_subtotal_cents,
            'fur_subtotal_cents',
              sc.fur_subtotal_cents,
            'show_fee_cents',
              sc.show_fee_cents,
            'discount_scope_eligible',
              case
                when v_discount_scope = 'both' then true
                when lower(sc.section_kind) = v_discount_scope then true
                else false
              end
          )
          order by
            sc.section_sort_order,
            sc.section_kind,
            sc.section_letter
        )
        from section_counts sc
        where sc.exhibitor_id = et.exhibitor_id
      ), '[]'::jsonb) as section_breakdown,

      jsonb_build_object(
        'source', 'cart',
        'cart_id', p_cart_id,
        'show_id', v_show_id,
        'currency', v_currency,

        'discount_enabled', v_discount_enabled,
        'discount_type', v_discount_type,
        'discount_value', v_discount_value,
        'discount_basis', v_discount_basis,
        'discount_scope', v_discount_scope,
        'discount_min_entries', v_discount_min_entries,
        'discount_max_entries', v_discount_max_entries,
        'discount_required_shows', v_discount_required_shows,

        'eligible_entry_count',
          et.eligible_entry_count,
        'eligible_show_count',
          et.eligible_show_count,
        'qualifying_show_count',
          et.qualifying_show_count,
        'qualifying_entry_count',
          et.qualifying_entry_count,
        'discounted_show_count',
          et.discounted_show_count,

        'entry_count', et.entry_count,
        'fur_count', et.fur_count,

        'entries_subtotal_cents',
          et.entries_subtotal_cents,

        'fur_subtotal_cents',
          et.fur_subtotal_cents,

        'show_fee_subtotal_cents',
          et.show_fee_subtotal_cents,

        'subtotal_before_discount_cents',
          et.subtotal_before_discount_cents,

        'discount_cents',
          least(
            greatest(et.discount_cents, 0),
            et.entries_subtotal_cents
          ),

        'calculated_total_cents',
          greatest(
            et.subtotal_before_discount_cents
            - least(
                greatest(et.discount_cents, 0),
                et.entries_subtotal_cents
              ),
            0
          )
      ) as fee_snapshot

    from exhibitor_totals et

    left join public.exhibitors ex
      on ex.id = et.exhibitor_id
  ),

  upserted as (
    insert into public.show_exhibitor_balances (
      show_id,
      exhibitor_id,
      exhibitor_user_id,
      entry_cart_id,
      cart_id,
      currency,
      entry_count,
      fur_count,
      entries_subtotal_cents,
      fur_subtotal_cents,
      show_fee_subtotal_cents,
      subtotal_before_discount_cents,
      discount_cents,
      calculated_total_cents,
      paid_online_cents,
      paid_manual_cents,
      refunded_cents,
      balance_due_cents,
      payment_status,
      latest_show_payment_id,
      latest_checkout_session_id,
      latest_payment_intent_id,
      section_breakdown,
      fee_snapshot,
      source,
      calculated_at,
      updated_at
    )
    select
      v_show_id,
      fr.exhibitor_id,
      fr.exhibitor_user_id,
      p_cart_id,
      p_cart_id,
      v_currency,
      fr.entry_count,
      fr.fur_count,
      fr.entries_subtotal_cents,
      fr.fur_subtotal_cents,
      fr.show_fee_subtotal_cents,
      fr.subtotal_before_discount_cents,
      fr.discount_cents,
      fr.calculated_total_cents,
      0,
      0,
      0,
      fr.calculated_total_cents,

      case
        when fr.calculated_total_cents <= 0 then 'paid'
        else 'unpaid'
      end,

      null,
      null,
      null,
      fr.section_breakdown,
      fr.fee_snapshot,
      'cart',
      now(),
      now()

    from final_rows fr

    on conflict (entry_cart_id, exhibitor_id)
      where (
        entry_cart_id is not null
        and exhibitor_id is not null
        and source = 'cart'
      )

    do update set
      show_id = excluded.show_id,
      exhibitor_user_id = excluded.exhibitor_user_id,
      cart_id = excluded.cart_id,
      currency = excluded.currency,
      entry_count = excluded.entry_count,
      fur_count = excluded.fur_count,
      entries_subtotal_cents =
        excluded.entries_subtotal_cents,
      fur_subtotal_cents =
        excluded.fur_subtotal_cents,
      show_fee_subtotal_cents =
        excluded.show_fee_subtotal_cents,
      subtotal_before_discount_cents =
        excluded.subtotal_before_discount_cents,
      discount_cents =
        excluded.discount_cents,
      calculated_total_cents =
        excluded.calculated_total_cents,
      paid_online_cents = 0,
      paid_manual_cents = 0,
      refunded_cents = 0,
      balance_due_cents =
        excluded.calculated_total_cents,

      payment_status = case
        when excluded.calculated_total_cents <= 0 then 'paid'
        else 'unpaid'
      end,

      latest_show_payment_id = null,
      latest_checkout_session_id = null,
      latest_payment_intent_id = null,
      section_breakdown =
        excluded.section_breakdown,
      fee_snapshot =
        excluded.fee_snapshot,
      source = 'cart',
      calculated_at = now(),
      updated_at = now()

    returning public.show_exhibitor_balances.*
  )

  select *
  from upserted
  order by exhibitor_id;
end;
$function$;



CREATE OR REPLACE FUNCTION public.calculate_entry_cart_balance_internal(p_cart_id uuid)
 RETURNS SETOF show_exhibitor_balances
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_show_id uuid;
  v_enabled boolean := false;
  v_type text := 'amount';
  v_value numeric := 0;
  v_scope text := 'both';
  v_show_letters text[] := '{}'::text[];
begin
  perform 1
  from public.calculate_entry_cart_balance_without_canada_special(p_cart_id);

  select c.show_id
  into v_show_id
  from public.entry_carts c
  where c.id = p_cart_id;

  select
    coalesce(sfs.canada_special_discount_enabled, false),
    lower(coalesce(sfs.canada_special_discount_type, 'amount')),
    greatest(coalesce(sfs.canada_special_discount_value, 0), 0),
    lower(coalesce(sfs.canada_special_discount_scope, 'both')),
    coalesce(sfs.canada_special_show_letters, '{}'::text[])
  into v_enabled, v_type, v_value, v_scope, v_show_letters
  from public.show_fee_settings sfs
  where sfs.show_id = v_show_id;

  if coalesce(v_enabled, false) then
    with canada_discount_by_exhibitor as (
      select
        eci.exhibitor_id,
        round(
          sum(
            least(
              coalesce(sffs.fee_per_entry, 0),
              greatest(
                case
                  when v_type = 'fixed_rate' then
                    coalesce(sffs.fee_per_entry, 0) - v_value
                  when v_type = 'percent' then
                    coalesce(sffs.fee_per_entry, 0)
                    * case when v_value <= 1 then v_value else v_value / 100 end
                  when v_type = 'amount' then v_value
                  else 0
                end,
                0
              )
            )
          ) * 100
        )::integer as special_discount_cents
      from (select * from checkout_private.pricing_items(p_cart_id) where not is_show_addon_carrier) eci
      join public.exhibitors exhibitor
        on exhibitor.id = eci.exhibitor_id
      join public.show_sections section
        on section.id = eci.section_id
       and section.show_id = v_show_id
      left join public.show_section_fee_settings sffs
        on sffs.section_id = eci.section_id
      where eci.cart_id = p_cart_id
        and not coalesce(eci.is_fur, false)
        and public.is_canadian_exhibitor_address(
          exhibitor.state,
          exhibitor.zip
        )
        and (
          v_scope = 'both'
          or lower(section.kind::text) = v_scope
        )
        and (
          cardinality(v_show_letters) = 0
          or exists (
            select 1
            from unnest(v_show_letters) as selected_letter
            where upper(btrim(selected_letter)) = upper(btrim(section.letter))
          )
        )
      group by eci.exhibitor_id
    ), chosen_discounts as (
      select
        balance.id,
        balance.discount_cents as volume_discount_cents,
        greatest(
          balance.discount_cents,
          canada.special_discount_cents
        )::integer as chosen_discount_cents,
        canada.special_discount_cents
      from public.show_exhibitor_balances balance
      join canada_discount_by_exhibitor canada
        on canada.exhibitor_id = balance.exhibitor_id
      where balance.entry_cart_id = p_cart_id
        and balance.source = 'cart'
    )
    update public.show_exhibitor_balances balance
    set
      discount_cents = chosen.chosen_discount_cents,
      calculated_total_cents = greatest(
        balance.subtotal_before_discount_cents - chosen.chosen_discount_cents,
        0
      ),
      balance_due_cents = greatest(
        balance.subtotal_before_discount_cents
          - chosen.chosen_discount_cents
          - balance.paid_online_cents
          - balance.paid_manual_cents
          + balance.refunded_cents,
        0
      ),
      payment_status = case
        when greatest(
          balance.subtotal_before_discount_cents
            - chosen.chosen_discount_cents
            - balance.paid_online_cents
            - balance.paid_manual_cents
            + balance.refunded_cents,
          0
        ) = 0 then 'paid'
        else 'unpaid'
      end,
      fee_snapshot = coalesce(balance.fee_snapshot, '{}'::jsonb)
        || jsonb_build_object(
          'discount_strategy', 'better_discount',
          'volume_discount_cents', chosen.volume_discount_cents,
          'special_discount_eligible', true,
          'special_discount_cents', chosen.special_discount_cents,
          'applied_discount', case
            when chosen.special_discount_cents > chosen.volume_discount_cents
              then 'special'
            when chosen.volume_discount_cents > 0 then 'volume'
            else 'none'
          end,
          'discount_cents', chosen.chosen_discount_cents,
          'calculated_total_cents', greatest(
            balance.subtotal_before_discount_cents
              - chosen.chosen_discount_cents,
            0
          )
        ),
      calculated_at = now(),
      updated_at = now()
    from chosen_discounts chosen
    where balance.id = chosen.id;
  end if;

  return query
  select balance.*
  from public.show_exhibitor_balances balance
  where balance.entry_cart_id = p_cart_id
    and balance.source = 'cart'
  order by balance.exhibitor_id;
end;
$function$;


