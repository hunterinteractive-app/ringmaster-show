-- Keep access account-based, but retain the selected person for each role.
alter table public.role_assignments
  add column if not exists exhibitor_id uuid references public.exhibitors(id) on delete set null,
  add column if not exists staff_name text;
drop index if exists public.role_assignments_unique;
create index if not exists role_assignments_user_show_idx on public.role_assignments(user_id,show_id);
create index if not exists role_assignments_exhibitor_idx on public.role_assignments(exhibitor_id) where exhibitor_id is not null;

create or replace function public.assign_show_staff_person(
  p_show_id uuid, p_user_id uuid, p_role text, p_exhibitor_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_name text;
begin
  if auth.uid() is null or not (
    public.is_super_admin(auth.uid())
    or exists(select 1 from public.shows where id=p_show_id and owner_user_id=auth.uid())
    or exists(select 1 from public.role_assignments where user_id=auth.uid()
      and (role='super_admin' or (show_id=p_show_id and role='admin')))
  ) then raise exception 'You do not have permission to manage staff roles for this show.' using errcode='42501'; end if;
  if p_role is null or p_role not in ('admin','superintendent','reporting_clerk') then
    raise exception 'Invalid staff role';
  end if;
  if p_exhibitor_id is not null then
    select coalesce(nullif(btrim(concat_ws(' ',first_name,last_name)),''),nullif(btrim(display_name),''))
      into v_name from public.exhibitors
      where id=p_exhibitor_id and owner_user_id=p_user_id
        and coalesce(is_active,true) and not coalesce(is_merged,false);
    if not found then raise exception 'Selected exhibitor does not belong to this account.' using errcode='22023'; end if;
  end if;
  insert into public.role_assignments(show_id,user_id,role,exhibitor_id,staff_name)
    values(p_show_id,p_user_id,p_role::public.app_role,p_exhibitor_id,v_name)
    on conflict(show_id,user_id,role) do update set
      exhibitor_id=coalesce(excluded.exhibitor_id,role_assignments.exhibitor_id),
      staff_name=coalesce(excluded.staff_name,role_assignments.staff_name)
    returning id into v_id;
  return v_id;
end $$;
revoke all on function public.assign_show_staff_person(uuid,uuid,text,uuid) from public,anon;
grant execute on function public.assign_show_staff_person(uuid,uuid,text,uuid) to authenticated,service_role;

-- Older clients must not replace another role on a shared login.
create or replace function public.assign_show_staff_role(p_show_id uuid,p_user_id uuid,p_role text)
returns uuid language sql security invoker set search_path = '' as $$
  select public.assign_show_staff_person(p_show_id,p_user_id,p_role,null::uuid);
$$;
revoke all on function public.assign_show_staff_role(uuid,uuid,text) from public,anon;
grant execute on function public.assign_show_staff_role(uuid,uuid,text) to authenticated,service_role;

-- Reuse the people already assigned to a show when print packs and closeout
-- need contact details.  This intentionally returns one latest assignment per
-- role and leaves the caller responsible for preserving any show details that
-- were already entered manually.
create or replace function public.show_role_contact_defaults(p_show_id uuid)
returns table (
  secretary_name text,
  secretary_address text,
  secretary_email text,
  secretary_phone text,
  superintendent_name text,
  superintendent_arba_number text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not (
    public.is_super_admin(auth.uid())
    or exists (
      select 1
      from public.shows s
      where s.id = p_show_id
        and s.owner_user_id = auth.uid()
    )
    or exists (
      select 1
      from public.role_assignments ra
      where ra.user_id = auth.uid()
        and (
          ra.role = 'super_admin'
          or (
            ra.show_id = p_show_id
            and ra.role in ('admin', 'superintendent', 'reporting_clerk')
          )
        )
    )
  ) then
    raise exception 'You do not have permission to view role contact defaults for this show.'
      using errcode = '42501';
  end if;

  return query
  with assigned_contacts as (
    select distinct on (ra.role)
      ra.role::text as role_name,
      coalesce(
        nullif(btrim(ra.staff_name), ''),
        nullif(btrim(e.display_name), ''),
        nullif(btrim(e.showing_name), ''),
        nullif(btrim(concat_ws(' ', e.first_name, e.last_name)), ''),
        nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
        nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
        nullif(btrim(u.email), '')
      ) as name,
      nullif(
        btrim(concat_ws(
          E'\n',
          nullif(btrim(e.address_line1), ''),
          nullif(btrim(e.address_line2), ''),
          nullif(btrim(concat_ws(' ', e.city, e.state, e.zip)), '')
        )),
        ''
      ) as address,
      coalesce(nullif(btrim(e.email), ''), nullif(btrim(u.email), '')) as email,
      nullif(btrim(e.phone), '') as phone,
      nullif(btrim(e.arba_number), '') as arba_number
    from public.role_assignments ra
    left join public.profiles p on p.id = ra.user_id
    left join lateral (
      select ex.*
      from public.exhibitors ex
      where ex.owner_user_id = ra.user_id
        and coalesce(ex.is_active, true)
        and not coalesce(ex.is_merged, false)
      order by
        case when ex.id = ra.exhibitor_id then 0 else 1 end,
        case when ex.id = p.primary_exhibitor_id then 0 else 1 end,
        case when ex.type::text = 'adult' then 0 else 1 end,
        ex.updated_at desc nulls last,
        ex.created_at desc nulls last
      limit 1
    ) e on true
    left join auth.users u on u.id = ra.user_id
    where ra.show_id = p_show_id
      and ra.role in ('admin', 'superintendent')
    order by ra.role, ra.created_at desc, ra.id desc
  )
  select
    (select name from assigned_contacts where role_name = 'admin'),
    (select address from assigned_contacts where role_name = 'admin'),
    (select email from assigned_contacts where role_name = 'admin'),
    (select phone from assigned_contacts where role_name = 'admin'),
    (select name from assigned_contacts where role_name = 'superintendent'),
    (select arba_number from assigned_contacts where role_name = 'superintendent');
end;
$$;

revoke all on function public.show_role_contact_defaults(uuid) from public, anon;
grant execute on function public.show_role_contact_defaults(uuid)
  to authenticated, service_role;
