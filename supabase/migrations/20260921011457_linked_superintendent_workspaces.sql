-- Group logistics only. Entries, payments, results and reports stay show-scoped.
create table public.superintendent_workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  show_ids uuid[] not null check (cardinality(show_ids) >= 2),
  created_at timestamptz not null default now()
);
alter table public.superintendent_workspaces enable row level security;
revoke all on public.superintendent_workspaces from public, anon, authenticated;
grant select on public.superintendent_workspaces to authenticated;
grant all on public.superintendent_workspaces to service_role;

create function public.can_view_superintendent_workspace(p_show_ids uuid[])
returns boolean language sql stable security invoker set search_path = '' as $$
  select auth.uid() is not null and cardinality(p_show_ids) >= 2
    and not exists (select 1 from unnest(p_show_ids) s(id)
      where not coalesce(public.user_can_view_show_lineup(s.id), false));
$$;
revoke all on function public.can_view_superintendent_workspace(uuid[]) from public, anon;
grant execute on function public.can_view_superintendent_workspace(uuid[]) to authenticated, service_role;
create policy superintendent_workspace_read on public.superintendent_workspaces
for select to authenticated using (public.can_view_superintendent_workspace(show_ids));

-- Cover updates from the existing individual lineup tools as well, so a
-- stale shared editor cannot overwrite changes made through those screens.
create function public.touch_lineup_assignment_version()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin new.updated_at := clock_timestamp(); return new; end;
$$;
revoke all on function public.touch_lineup_assignment_version() from public, anon, authenticated;
create trigger touch_lineup_assignment_version before update on public.show_judging_assignments
for each row execute function public.touch_lineup_assignment_version();

-- Uses existing row policies as well as checking access to every linked show.
-- Only logistical fields change; never move an assignment between shows.
create function public.save_workspace_assignment(
  p_workspace_id uuid, p_id uuid, p_table text,
  p_order integer, p_status text, p_expected_updated_at timestamptz
) returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_shows uuid[]; v_existing public.show_judging_assignments;
begin
  select show_ids into v_shows from public.superintendent_workspaces where id=p_workspace_id;
  if auth.uid() is null or v_shows is null
     or exists(select 1 from unnest(v_shows) s(id) where not coalesce(public.user_can_manage_show_lineup(s.id),false)) then
    raise exception 'You need superintendent access to both shows.' using errcode='42501';
  end if;
  if p_status is null or p_status not in ('draft','in_progress','completed') or p_order is null or p_order<0 then
    raise exception 'Choose a valid judging status and order.';
  end if;
  select * into v_existing from public.show_judging_assignments where id=p_id for update;
  if not found or not (v_existing.show_id=any(v_shows)) then
    raise exception 'Assignment does not belong to this workspace.' using errcode='42501';
  end if;
  if p_expected_updated_at is null or v_existing.updated_at is distinct from p_expected_updated_at then
    raise exception 'Another superintendent changed this assignment. Refresh and try again.' using errcode='40001';
  end if;
  update public.show_judging_assignments set
    table_number=nullif(btrim(p_table),''),sort_order=p_order,status=p_status,
    completed_at=case when p_status='completed' then coalesce(completed_at,now()) end,
    completed_by=case when p_status='completed' then coalesce(completed_by,auth.uid()) end,
    updated_at=clock_timestamp() where id=p_id;
  if not found then raise exception 'Assignment could not be updated.' using errcode='42501'; end if;
  return p_id;
end;
$$;
revoke all on function public.save_workspace_assignment(uuid,uuid,text,integer,text,timestamptz) from public, anon;
grant execute on function public.save_workspace_assignment(uuid,uuid,text,integer,text,timestamptz) to authenticated;

-- Resolve the requested event by name/date; do not embed environment-specific IDs.
insert into public.superintendent_workspaces(name,show_ids)
select 'Miss Sala Bash & Fall Duneabash', array_agg(id order by name desc)
from public.shows where start_date::date=date '2026-09-26' and name in (
  'Miss Sala Bash Rabbit Show',
  'Fall Duneabash Show (in conjunction with Miss-Sala-Bash RBA double show)')
having count(*)=2;
