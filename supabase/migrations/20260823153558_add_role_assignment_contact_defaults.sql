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
    exists (
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
