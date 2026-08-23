-- Club membership is the authority boundary for hosting-club management.
-- A show-level secretary/admin is not automatically a club manager.

create or replace function public.get_hosting_clubs_for_user(
  p_user_id uuid default auth.uid()
)
returns table (
  id uuid,
  name text,
  role text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
     or (
       p_user_id is distinct from (select auth.uid())
       and not public.is_super_admin()
     ) then
    raise exception 'Not authorized to view club memberships'
      using errcode = '42501';
  end if;

  return query
  select c.id, c.name, cm.role
  from public.club_members cm
  join public.clubs c on c.id = cm.club_id
  where cm.user_id = p_user_id
    and coalesce(cm.is_active, true)
    and coalesce(c.is_active, true)
  order by lower(c.name), c.id;
end;
$$;

create or replace function public.has_active_secretary_license_for_user(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
    p_user_id = (select auth.uid())
    or public.is_super_admin()
  )
  and exists (
    select 1
    from public.account_license_balances alb
    where alb.user_id = p_user_id
      and alb.can_change_host_club
      and (
        alb.secretary_license_expires_at is null
        or alb.secretary_license_expires_at > now()
      )
  );
$$;

create or replace function public.user_can_manage_hosting_club(
  p_club_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (
    p_user_id = (select auth.uid())
    or public.is_super_admin()
  )
  and exists (
    select 1
    from public.club_members cm
    where cm.club_id = p_club_id
      and cm.user_id = p_user_id
      and coalesce(cm.is_active, true)
      and lower(coalesce(cm.role, '')) in ('owner', 'manager')
  );
$$;

create or replace function public.rename_hosting_club(
  p_club_id uuid,
  p_name text
)
returns table (
  id uuid,
  name text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := btrim(p_name);
begin
  if v_name is null or v_name = '' then
    raise exception 'Club name is required' using errcode = '22023';
  end if;

  if not public.user_can_manage_hosting_club(p_club_id) then
    raise exception 'Not authorized to manage this hosting club'
      using errcode = '42501';
  end if;

  return query
  update public.clubs
     set name = v_name
   where clubs.id = p_club_id
  returning clubs.id, clubs.name;
end;
$$;

revoke all on function public.get_hosting_clubs_for_user(uuid) from public;
revoke all on function public.has_active_secretary_license_for_user(uuid) from public;
revoke all on function public.user_can_manage_hosting_club(uuid, uuid) from public;
revoke all on function public.rename_hosting_club(uuid, text) from public;

grant execute on function public.get_hosting_clubs_for_user(uuid) to authenticated;
grant execute on function public.has_active_secretary_license_for_user(uuid) to authenticated;
grant execute on function public.user_can_manage_hosting_club(uuid, uuid) to authenticated;
grant execute on function public.rename_hosting_club(uuid, text) to authenticated;

-- This prior public INSERT policy allowed any signed-in user to add their own
-- membership row to any club if they learned its id.
drop policy if exists "Users can join clubs they create" on public.club_members;
