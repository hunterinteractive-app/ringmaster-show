-- Read-only support inspection; checkout continues to require household access.
create or replace function public.support_submitted_balances(p_show_id uuid,p_target_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.is_super_admin() then
  raise exception 'Only super administrators can inspect support balances.' using errcode='42501';
 end if;
 if p_target_user_id is null then
  raise exception 'A target user is required.' using errcode='22004';
 end if;
 return (select coalesce(jsonb_agg(row_to_json(r) order by r.submitted_at),'[]'::jsonb) from (
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
 where auth.uid() is not null and household_private.has_access(c.user_id,p_target_user_id)
   and c.show_id=p_show_id and c.status='submitted' and c.payment_status<>'paid'
 group by c.id,s.id,ps.stripe_enabled having sum(b.balance_due_cents)>0
 ) r );
end;
$$;
revoke all on function public.support_submitted_balances(uuid,uuid) from public,anon;
grant execute on function public.support_submitted_balances(uuid,uuid) to authenticated;
