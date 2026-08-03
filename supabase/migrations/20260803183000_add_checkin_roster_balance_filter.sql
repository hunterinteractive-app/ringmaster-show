drop function if exists public.get_show_checkin_roster(uuid, text, text);

create function public.get_show_checkin_roster(
  p_show_id uuid,
  p_search text default '',
  p_status text default 'all'
)
returns table (
  exhibitor_id uuid,
  exhibitor_name text,
  exhibitor_number text,
  checkin_status text,
  completed_at timestamptz,
  balance_due_cents integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_status text := lower(btrim(coalesce(p_status, 'all')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in roster.' using errcode = '42501';
  end if;
  if v_status not in ('all', 'balance_due', 'not_started', 'in_progress', 'completed', 'reviewed_by_secretary', 'locked') then
    raise exception 'Invalid check-in status.' using errcode = '22023';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    coalesce(r.status, 'not_started'),
    r.completed_at,
    coalesce(b.balance_due_cents, 0)::integer
  from public.entries e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id
  left join lateral (
    select coalesce(sum(balance_due_cents), 0)::integer as balance_due_cents
    from public.show_exhibitor_balances
    where show_id = p_show_id and exhibitor_id = e.exhibitor_id
  ) b on true
  where e.show_id = p_show_id
    and (v_status = 'all' or v_status = 'balance_due' or coalesce(r.status, 'not_started') = v_status)
    and (v_status <> 'balance_due' or coalesce(b.balance_due_cents, 0) > 0)
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  group by e.exhibitor_id, x.display_name, x.first_name, x.last_name, x.exhibitor_number, r.status, r.completed_at, b.balance_due_cents
  order by coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '')))
  limit 500;
end;
$$;

revoke all on function public.get_show_checkin_roster(uuid, text, text) from public, anon;
grant execute on function public.get_show_checkin_roster(uuid, text, text) to authenticated, service_role;
