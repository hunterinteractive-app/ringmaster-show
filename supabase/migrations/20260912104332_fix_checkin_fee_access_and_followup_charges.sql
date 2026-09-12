-- Internal bookkeeping is reached only through authorized check-in/report RPCs.
alter table public.show_checkin_fee_carts enable row level security;
alter table public.show_checkin_fee_charges enable row level security;
revoke all on table public.show_checkin_fee_carts, public.show_checkin_fee_charges from public, anon, authenticated;
grant select,insert,update,delete on table public.show_checkin_fee_carts, public.show_checkin_fee_charges to service_role;

-- Remove the unauthenticated helper from the exposed API schema entirely.
alter function public.add_checkin_fee_charge(uuid,uuid,uuid,text,integer,jsonb)
  set schema report_generation_private;
revoke all on function report_generation_private.add_checkin_fee_charge(uuid,uuid,uuid,text,integer,jsonb) from public,anon,authenticated;
grant execute on function report_generation_private.add_checkin_fee_charge(uuid,uuid,uuid,text,integer,jsonb) to service_role;

CREATE OR REPLACE FUNCTION report_generation_private.add_checkin_fee_charge(p_show_id uuid, p_exhibitor_id uuid, p_change_request_id uuid, p_action_key text, p_amount_cents integer, p_breakdown jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cart public.entry_carts%rowtype;
  v_user_id uuid;
  v_section_id uuid;
  v_before integer := 0;
  v_after integer := 0;
  v_carrier_id uuid;
  v_charge_id uuid;
  v_existing public.show_checkin_fee_charges%rowtype;
  v_recorded_fees integer;
begin
  if p_amount_cents = 0 then return null; end if;
  -- Serialize new fee carts and same-request replays for this exhibitor.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'checkin-fee:' || p_show_id::text || ':' || p_exhibitor_id::text, 0));
  if p_change_request_id is not null then
    select * into v_existing from public.show_checkin_fee_charges
    where change_request_id=p_change_request_id and action_key=p_action_key;
    if found then
      if v_existing.show_id is distinct from p_show_id
        or v_existing.exhibitor_id is distinct from p_exhibitor_id
        or v_existing.amount_cents is distinct from p_amount_cents
        or v_existing.breakdown is distinct from coalesce(p_breakdown, '{}'::jsonb)
        or v_existing.voided_at is not null then
        raise exception 'This fee was already recorded with different details. Submit a new change request.' using errcode='22023';
      end if;
      return v_existing.id;
    end if;
  end if;
  select c.* into v_cart from public.entry_carts c
  where c.show_id = p_show_id and c.status = 'active' and c.payment_status not in ('paid', 'pending', 'refunded')
    and c.active_payment_session_id is null and c.completed_payment_session_id is null
    -- A cash payment freezes its balance even if the cart still says unpaid.
    -- Later fees get a new cart; the original payment history stays untouched.
    and not exists (select 1 from public.show_exhibitor_balances b
      where b.entry_cart_id=c.id and (
        b.paid_online_cents<>0 or b.paid_manual_cents<>0 or b.refunded_cents<>0
        or b.payment_status in ('pending','partial','paid','overpaid','refunded')))
    and c.user_id in (
      select coalesce(e.exhibitor_user_id, x.owner_user_id, x.claimed_by_user_id)
      from public.exhibitors x left join public.entries e on e.exhibitor_id = x.id and e.show_id = p_show_id
      where x.id = p_exhibitor_id order by e.updated_at desc nulls last limit 1
    )
  order by c.updated_at desc limit 1 for update;
  if not found then
    select coalesce(owner_user_id, claimed_by_user_id, (select exhibitor_user_id from public.entries where show_id=p_show_id and exhibitor_id=p_exhibitor_id order by updated_at desc limit 1))
      into v_user_id from public.exhibitors where id = p_exhibitor_id;
    if v_user_id is null then raise exception 'This exhibitor does not have an account-backed cart. Please see the show secretary.'; end if;
    insert into public.entry_carts(user_id, show_id, status, payment_status, subtotal_cents, total_cents, currency)
      values(v_user_id, p_show_id, 'active', 'unpaid', 0, 0, 'usd') returning * into v_cart;
  end if;
  if not exists (select 1 from public.show_checkin_fee_carts where cart_id = v_cart.id) then
    select coalesce(sum(balance_due_cents), 0)::integer into v_before
      from public.show_exhibitor_balances where entry_cart_id = v_cart.id and exhibitor_id = p_exhibitor_id and source = 'cart';
    select id into v_section_id from public.show_sections where show_id = p_show_id order by sort_order, id limit 1;
    if v_section_id is null then raise exception 'This show has no entry section for a check-in fee.'; end if;
    insert into public.entry_cart_items(cart_id, section_id, exhibitor_id, species, tattoo, is_checkin_fee_carrier)
      values(v_cart.id, v_section_id, p_exhibitor_id, 'rabbit', 'CHECKIN-FEE', true) returning id into v_carrier_id;
    perform public.calculate_entry_cart_balance_internal(v_cart.id);
    select coalesce(sum(balance_due_cents), 0)::integer into v_after
      from public.show_exhibitor_balances where entry_cart_id = v_cart.id and exhibitor_id = p_exhibitor_id and source = 'cart';
    insert into public.show_checkin_fee_carts(cart_id, exhibitor_id, carrier_item_id, carrier_base_cents)
      values(v_cart.id, p_exhibitor_id, v_carrier_id, greatest(v_after - v_before, 0));
  end if;
  insert into public.show_checkin_fee_charges(show_id, exhibitor_id, cart_id, change_request_id, action_key, amount_cents, breakdown)
    values(p_show_id, p_exhibitor_id, v_cart.id, p_change_request_id, p_action_key, p_amount_cents, coalesce(p_breakdown, '{}'::jsonb))
    on conflict (change_request_id, action_key) where change_request_id is not null do update
      set amount_cents = excluded.amount_cents, breakdown = excluded.breakdown, voided_at = null
    returning id into v_charge_id;
  perform public.calculate_entry_cart_balance_internal(v_cart.id);
  -- If a concurrent payment froze this cart, roll back the new charge rather
  -- than accepting a fee that was not included in its balance.
  select coalesce(sum(amount_cents),0)::integer into v_recorded_fees
    from public.show_checkin_fee_charges where cart_id=v_cart.id
    and exhibitor_id=p_exhibitor_id and voided_at is null;
  if not exists (select 1 from public.show_exhibitor_balances b
    where b.entry_cart_id=v_cart.id and b.exhibitor_id=p_exhibitor_id
    and (b.fee_snapshot->>'checkin_action_fee_cents')::integer=v_recorded_fees) then
    raise exception 'The balance changed while adding this fee. Please retry the change.' using errcode='40001';
  end if;
  return v_charge_id;
end;
$function$;

-- Preserve current authorized entrypoints and their grants while rebinding
-- their internal calls to the private schema. Fail if a dependency is missing.
do $migration$
declare signature text; definition text;
begin
  foreach signature in array array[
    'public.submit_exhibitor_checkin_change_request(text,uuid,text,jsonb,text)',
    'public.submit_exhibitor_checkin_add_entry(text,jsonb,text)',
    'public.review_checkin_change_request(uuid,boolean,text)'
  ] loop
    definition := pg_get_functiondef(signature::regprocedure);
    if strpos(definition,'public.add_checkin_fee_charge(')=0 then
      raise exception 'Missing expected fee helper call in %',signature;
    end if;
    execute replace(definition,'public.add_checkin_fee_charge(',
      'report_generation_private.add_checkin_fee_charge(');
  end loop;
end;
$migration$;

-- Preserve payment protection outside this authorized cash-payment RPC.
CREATE OR REPLACE FUNCTION public.record_checkin_manual_payment(p_show_id uuid, p_exhibitor_id uuid, p_amount_cents integer, p_method text, p_reference text DEFAULT NULL::text, p_receipt_preference text DEFAULT 'no_receipt'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  b public.show_exhibitor_balances%rowtype;
  pid uuid;
  m text := lower(btrim(coalesce(p_method, '')));
  v_total_due integer := 0;
  v_remaining integer := p_amount_cents;
  v_apply integer;
  v_currency text;
  v_previous_write text := current_setting('ringmaster.payment_state_write',true);
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if p_amount_cents <= 0 or m not in ('cash', 'check', 'digital', 'stripe', 'square', 'paypal') then
    raise exception 'Invalid payment';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'checkin-fee:' || p_show_id::text || ':' || p_exhibitor_id::text,0));

  for b in
    select * from public.show_exhibitor_balances
    where show_id = p_show_id and exhibitor_id = p_exhibitor_id
    for update
  loop
    v_total_due := v_total_due + greatest(coalesce(b.balance_due_cents, 0), 0);
    v_currency := coalesce(v_currency, b.currency);
  end loop;
  if v_total_due <= 0 then raise exception 'This exhibitor does not have a balance due.'; end if;
  if p_amount_cents > v_total_due then
    raise exception 'Payment amount cannot exceed the outstanding balance.' using errcode = '22023';
  end if;

  -- The caller has been authorized and all balances are locked. Permit only
  -- this payment operation to update a previously paid/partial balance.
  perform set_config('ringmaster.payment_state_write','on',true);
  insert into public.show_payments(
    show_id, exhibitor_id, currency, status, payment_status, payment_method,
    payment_method_type, payment_type, provider, amount_cents, total_cents, paid_at, metadata
  ) values (
    p_show_id, p_exhibitor_id, coalesce(v_currency, 'usd'), 'paid', 'paid', m,
    m, 'manual', m, p_amount_cents, p_amount_cents, now(),
    jsonb_build_object('reference', p_reference, 'receipt_preference', p_receipt_preference, 'source', 'checkin')
  ) returning id into pid;

  for b in
    select * from public.show_exhibitor_balances
    where show_id = p_show_id and exhibitor_id = p_exhibitor_id and balance_due_cents > 0
    order by updated_at desc
  loop
    exit when v_remaining <= 0;
    v_apply := least(v_remaining, b.balance_due_cents);
    update public.show_exhibitor_balances
    set paid_manual_cents = paid_manual_cents + v_apply,
        balance_due_cents = greatest(0, calculated_total_cents - paid_online_cents - (paid_manual_cents + v_apply) + refunded_cents),
        payment_status = case when calculated_total_cents <= paid_online_cents + paid_manual_cents + v_apply then 'paid' else 'partial' end,
        updated_at = now()
    where id = b.id;
    v_remaining := v_remaining - v_apply;
  end loop;
  if v_remaining <> 0 then raise exception 'Payment could not be applied to the outstanding balance.'; end if;

  perform set_config('ringmaster.payment_state_write',coalesce(v_previous_write,'off'),true);

  insert into public.show_checkin_audit_events(show_id, exhibitor_id, event_type, actor_type, actor_user_id, details)
  values(p_show_id, p_exhibitor_id, 'manual_payment_recorded', 'secretary', auth.uid(), jsonb_build_object('payment_id', pid, 'amount_cents', p_amount_cents, 'method', m));
  return jsonb_build_object('payment_id', pid, 'amount_cents', p_amount_cents);
end;
$function$;
