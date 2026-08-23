-- Day-of and mail-in entry staff need to find an existing RingMaster
-- exhibitor before that exhibitor has an entry in the current show.  Keep
-- the directory private to authorized staff and require a meaningful search
-- term so this is not a bulk directory export.
create or replace function public.search_registered_exhibitors_for_show(
  p_show_id uuid,
  p_search text
)
returns table (
  id uuid,
  showing_name text,
  display_name text,
  first_name text,
  last_name text,
  email text,
  phone text,
  address_line1 text,
  address_line2 text,
  city text,
  state text,
  zip text,
  arba_number text,
  type text,
  owner_user_id uuid,
  is_active boolean,
  is_local_only boolean,
  created_for_show_id uuid,
  is_merged boolean,
  merged_into_exhibitor_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to search the exhibitor directory for this show.'
      using errcode = '42501';
  end if;

  if char_length(v_search) < 2 then
    return;
  end if;

  return query
  select
    e.id,
    e.showing_name,
    e.display_name,
    e.first_name,
    e.last_name,
    e.email,
    e.phone,
    e.address_line1,
    e.address_line2,
    e.city,
    e.state,
    e.zip,
    e.arba_number,
    e.type::text,
    e.owner_user_id,
    e.is_active,
    e.is_local_only,
    e.created_for_show_id,
    e.is_merged,
    e.merged_into_exhibitor_id
  from public.exhibitors e
  where coalesce(e.is_active, true)
    and not coalesce(e.is_merged, false)
    and (
      lower(concat_ws(' ',
        e.showing_name,
        e.display_name,
        e.first_name,
        e.last_name,
        e.email,
        e.phone,
        e.arba_number,
        e.city,
        e.state,
        e.zip
      )) like '%' || v_search || '%'
    )
  order by
    coalesce(nullif(e.display_name, ''), nullif(e.showing_name, ''),
      nullif(trim(concat_ws(' ', e.first_name, e.last_name)), ''),
      '(Unnamed Exhibitor)'),
    e.created_at desc
  limit 50;
end;
$$;

revoke all on function public.search_registered_exhibitors_for_show(uuid, text)
  from public, anon;
grant execute on function public.search_registered_exhibitors_for_show(uuid, text)
  to authenticated, service_role;
