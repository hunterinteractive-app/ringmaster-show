-- The two-argument report was overwritten without the authoritative-source
-- filter. Keep both callers on one implementation to prevent future drift.
create or replace function public.report_show_exhibitor_balances_scoped(
  p_show_id uuid, p_section_ids uuid[]
)
returns setof jsonb
language sql stable security invoker
set search_path = ''
as $$
  select * from public.report_show_exhibitor_balances_scoped(
    p_show_id, p_section_ids, false
  );
$$;
revoke all on function public.report_show_exhibitor_balances_scoped(uuid,uuid[]) from public, anon;
grant execute on function public.report_show_exhibitor_balances_scoped(uuid,uuid[]) to authenticated, service_role;
comment on function public.report_show_exhibitor_balances_scoped(uuid,uuid[])
is 'Read-only scoped balances using authoritative entries snapshots; cart balances are fallback only. Delegates to the shared implementation without restricting to submitted carts.';
