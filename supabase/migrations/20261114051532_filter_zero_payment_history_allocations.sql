-- A shared cart may include other exhibitors. Zero-dollar portions are not
-- payment history for this exhibitor. Keep the original receipt only when used.
create or replace function public.get_show_finance_history(p_show_id uuid,p_exhibitor_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform show_finances_private.authorize(p_show_id);
 return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(e)-'request_id' order by created_at desc,id) from show_finances_private.events e
  where show_id=p_show_id and exhibitor_id=p_exhibitor_id),'[]'),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'original_exhibitor_id',p.exhibitor_id,
   'payer_name',coalesce(nullif(ex.showing_name,''),nullif(ex.display_name,''),concat_ws(' ',ex.first_name,ex.last_name)),
   'amount_cents',coalesce(p.amount_cents,p.total_cents,0),'refunded_cents',coalesce(p.refunded_cents,0),'currency',p.currency,
   'status',p.status,'method',coalesce(p.payment_method,p.provider),'recorded_externally',p.payment_type='manual',
   'reference',p.metadata->>'reference','paid_at',p.paid_at,'created_at',p.created_at,'balance_id',p.balance_id)
  order by p.created_at desc,p.id) from public.show_payments p left join public.exhibitors ex on ex.id=p.exhibitor_id
  where p.show_id=p_show_id and coalesce(p.payment_type,'')<>'legacy_cart_parent'
   and (p.exhibitor_id=p_exhibitor_id or p.balance_id in (
    select (a->>'balance_id')::uuid from public.show_exhibitor_balances b cross join lateral jsonb_array_elements(coalesce(b.fee_snapshot->'payment_allocations','[]')) a
    where b.show_id=p_show_id and b.exhibitor_id=p_exhibitor_id and b.source='entries' and (coalesce((a->>'paid_online_cents')::integer,0)<>0 or coalesce((a->>'paid_manual_cents')::integer,0)<>0 or coalesce((a->>'refunded_cents')::integer,0)<>0)))),'[]'),
 'allocations',coalesce((select jsonb_agg(a) from public.show_exhibitor_balances b cross join lateral jsonb_array_elements(coalesce(b.fee_snapshot->'payment_allocations','[]')) a where b.show_id=p_show_id and b.exhibitor_id=p_exhibitor_id and b.source='entries' and (coalesce((a->>'paid_online_cents')::integer,0)<>0 or coalesce((a->>'paid_manual_cents')::integer,0)<>0 or coalesce((a->>'refunded_cents')::integer,0)<>0)),'[]'));
end $$;
