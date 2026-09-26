-- Reprice checkout before reuse, bind it to exact cart contents, and serialize
-- cart edits with quote creation/finalization. Existing completed receipts stay intact.
create schema if not exists checkout_private;
revoke all on schema checkout_private from public, anon, authenticated;

create function checkout_private.cart_items(p_cart_id uuid)
returns jsonb language sql volatile set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(i) - 'created_at' - 'updated_at' order by i.id), '[]'::jsonb)
  from public.entry_cart_items i where i.cart_id=p_cart_id
$$;
revoke all on function checkout_private.cart_items(uuid) from public, anon, authenticated;

create function checkout_private.serialize_cart_edit()
returns trigger language plpgsql security definer set search_path='' as $$
declare c record;
begin
  -- Stable lock ordering also handles an item moved between carts.
  for c in select id, status, completed_payment_session_id from public.entry_carts
    where id in (case when tg_op<>'INSERT' then old.cart_id end,
                 case when tg_op<>'DELETE' then new.cart_id end)
    order by id for update
  loop
    if c.completed_payment_session_id is not null then
      raise exception 'This cart has already been paid. Start a new cart for additional entries.';
    end if;
  end loop;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function checkout_private.serialize_cart_edit() from public, anon, authenticated;
create trigger a_serialize_checkout_cart_edit before insert or update or delete
on public.entry_cart_items for each row execute function checkout_private.serialize_cart_edit();

do $migration$
declare d text; original text; reuse_block text; start_pos integer; end_pos integer;
begin
  d:=pg_get_functiondef('public.protect_cart_balance_after_payment_attempt()'::regprocedure);
  if strpos(d, '  if old.entry_cart_id is not null and (')=0 then raise exception 'Balance protection anchor changed'; end if;
  d:=replace(d, '  if old.entry_cart_id is not null and (', $code$
  if current_setting('ringmaster.checkout_reprice',true)='on'
     and old.source='cart' and old.paid_online_cents=0
     and old.paid_manual_cents=0 and old.refunded_cents=0 then
    new.payment_status:=old.payment_status;
    new.latest_show_payment_id:=old.latest_show_payment_id;
    new.latest_checkout_session_id:=old.latest_checkout_session_id;
    new.latest_payment_intent_id:=old.latest_payment_intent_id;
    return new;
  end if;
  if old.entry_cart_id is not null and ($code$);
  execute d;

  d:=pg_get_functiondef('public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)'::regprocedure);
  original:=d;
  start_pos:=strpos(d, '    if found'||chr(10)||'       and v_active.provider = v_provider');
  end_pos:=strpos(d, '    if found'||chr(10)||'       and v_active.provider = v_provider'||chr(10)||'       and v_active.attempt_status in (''created'', ''pending'', ''processing'')'||chr(10)||'       and v_active.expires_at is not null');
  if start_pos=0 or end_pos<=start_pos then raise exception 'Checkout reuse block changed'; end if;
  reuse_block:=substring(d from start_pos for end_pos-start_pos);
  d:=overlay(d placing '' from start_pos for end_pos-start_pos);
  reuse_block:=replace(reuse_block, 'if found', 'if v_active.id is not null');
  reuse_block:=replace(reuse_block, 'and v_active.provider = v_provider',
    'and v_active.quote_hash = v_quote_hash and v_active.quote_snapshot = v_snapshot'||chr(10)||'       and v_active.provider = v_provider');

  if strpos(d,'  perform public.calculate_entry_cart_balance(p_cart_id);')=0 then
    raise exception 'Checkout calculation anchor changed'; end if;
  d:=replace(d,'  perform public.calculate_entry_cart_balance(p_cart_id);', $code$
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
  perform public.calculate_entry_cart_balance(p_cart_id);
  perform set_config('ringmaster.checkout_reprice', 'off', true);
  update public.entry_carts set active_payment_session_id=v_cart.active_payment_session_id,
    payment_status=v_cart.payment_status where id=p_cart_id;
$code$);
  -- Exclude balance rows for exhibitors removed from the cart.
  d:=replace(d, 'entry_cart_id = p_cart_id and source = ''cart''',
    'entry_cart_id = p_cart_id and source = ''cart'' and exhibitor_id in (select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id)');
  d:=replace(d, 'b.entry_cart_id = p_cart_id and b.source = ''cart''',
    'b.entry_cart_id = p_cart_id and b.source = ''cart'' and b.exhibitor_id in (select exhibitor_id from public.entry_cart_items where cart_id=p_cart_id)');
  if strpos(d,'  v_quote_hash := encode(')=0 then raise exception 'Quote hash anchor changed'; end if;
  d:=replace(d,'  v_quote_hash := encode(',
    '  v_snapshot := v_snapshot || jsonb_build_object(''cart_items'', checkout_private.cart_items(p_cart_id));'||chr(10)||'  v_quote_hash := encode(');
  d:=replace(d,'  select count(*) + 1 into v_attempt_number',
    reuse_block||chr(10)||'  select count(*) + 1 into v_attempt_number');
  -- Superseded unpaid ledger rows must not remain collectible/pending.
  d:=replace(d,'  insert into public.show_payment_sessions (', $code$
  update public.show_payments set status='cancelled', payment_status='cancelled', updated_at=v_now
  where cart_id=p_cart_id and payment_session_id in
    (select id from public.show_payment_sessions where cart_id=p_cart_id and attempt_status='superseded')
    and status in ('pending','processing','requires_action');

  insert into public.show_payment_sessions ($code$);
  if d=original then raise exception 'Checkout function was not patched'; end if;
  execute d;

  d:=pg_get_functiondef('public.finalize_entry_cart_paid(uuid,uuid,text,text,integer,text)'::regprocedure);
  if strpos(d,'  if p_amount_cents is distinct from v_session.expected_amount_cents then')=0 then
    raise exception 'Finalizer amount check changed'; end if;
  d:=replace(d,'  if p_amount_cents is distinct from v_session.expected_amount_cents then', $code$
  -- Old quotes lack item identity and must be reviewed rather than silently
  -- attaching unpurchased items. The durable payment queue retains failures.
  if v_session.quote_snapshot->'cart_items' is distinct from checkout_private.cart_items(p_cart_id) then
    raise exception 'Cart changed after checkout was calculated. Refresh checkout before paying. If already charged, contact support; do not pay again.';
  end if;
  if p_amount_cents is distinct from v_session.expected_amount_cents then$code$);
  execute d;
end;
$migration$;
