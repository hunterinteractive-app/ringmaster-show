-- Restore confirmation on deployments missing the earlier RPC, including household authorization.
-- Fee-only carrier items represent charges and never create animal entries.
-- Confirm their paid ledger while requiring every regular/fur entry to exist.
create or replace function public.get_stripe_registration_status(p_checkout_session_id text default null, p_cart_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  a public.show_payment_sessions%rowtype;
  c public.entry_carts%rowtype;
  v_expected integer;
  v_items integer;
  v_actual integer;
  v_payments integer;
  v_paid integer;
  v_complete boolean;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if nullif(p_checkout_session_id,'') is null and p_cart_id is null then raise exception 'Payment reference required' using errcode='22023'; end if;
  select s.* into a from public.show_payment_sessions s join public.entry_carts cart on cart.id=s.cart_id
  where s.provider='stripe' and household_private.has_access(cart.user_id)
    and (p_checkout_session_id is null or s.provider_session_id=p_checkout_session_id)
    and (p_cart_id is null or s.cart_id=p_cart_id)
  order by (s.id=coalesce(cart.active_payment_session_id,cart.completed_payment_session_id)) desc nulls last,
    s.created_at desc,s.id desc limit 1;
  if a.id is null then raise exception 'Payment unavailable for this account' using errcode='42501'; end if;
  select * into strict c from public.entry_carts where id=a.cart_id;
  if a.attempt_status<>'finalized' or c.status<>'submitted' or c.payment_status is distinct from 'paid' then
    return jsonb_build_object('completed',false,'attempt_status',a.attempt_status);
  end if;
  select count(*),count(*) filter(where not is_checkin_fee_carrier)
    into v_items,v_expected from public.entry_cart_items where cart_id=c.id;
  select count(*) into v_actual from public.entries where source_cart_id=c.id and payment_session_id=a.id and payment_status='paid';
  select count(*),count(*) filter(where payment_status='paid') into v_payments,v_paid from public.show_payments where payment_session_id=a.id;
  v_complete := a.attempt_status='finalized' and c.status='submitted' and c.payment_status='paid'
    and c.completed_payment_session_id=a.id and v_items>0 and v_actual=v_expected and v_payments>0 and v_paid=v_payments
    and not exists (select 1 from public.entry_cart_items i where i.cart_id=c.id and not i.is_checkin_fee_carrier and not exists (
      select 1 from public.entries e where e.source_cart_id=c.id and e.source_cart_item_id=i.id
        and e.payment_session_id=a.id and e.payment_status='paid'
        and e.animal_id is not distinct from i.animal_id and e.exhibitor_id=i.exhibitor_id and e.section_id=i.section_id
        and e.cart_entry_kind=case when coalesce(i.is_fur,false) then 'fur' else 'entry' end));
  return jsonb_build_object('completed',v_complete,'attempt_status',a.attempt_status,
    'expected_entries',v_expected,'saved_paid_entries',v_actual,'payment_records',v_payments,'paid_records',v_paid);
end;
$$;
revoke all on function public.get_stripe_registration_status(text,uuid) from public, anon;
grant execute on function public.get_stripe_registration_status(text,uuid) to authenticated;
