-- School details remain private; entry-management staff may read only the
-- information submitted for this show or a contest hosted by this show.
create function show_registration_private.exhibitor_school(p_show_id uuid, p_exhibitor_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare school jsonb; applicable boolean;
begin
  if auth.uid() is null or not coalesce(public.user_can_manage_entries(p_show_id), false) then
    raise exception 'Entry management permission is required to view school information.' using errcode='42501';
  end if;

  if not exists(select 1 from show_registration_private.policy(p_show_id)) then
    return jsonb_build_object('applicable', false);
  end if;

  select exists (
    select 1 from public.entries e join public.show_sections s on s.id=e.section_id and s.show_id=e.show_id
    where e.show_id=p_show_id and e.exhibitor_id=p_exhibitor_id and lower(s.kind::text)='youth'
  ) or exists (
    select 1 from show_addons_private.selections r join public.entry_carts c on c.id=r.cart_id
    where r.show_id=p_show_id and r.exhibitor_id=p_exhibitor_id and r.kind='contest' and c.status='submitted'
      and exists(select 1 from show_registration_private.youth_exhibitors(c.id) y where y.exhibitor_id=p_exhibitor_id)
  ) into applicable;

  if not applicable then return jsonb_build_object('applicable', false); end if;

  select jsonb_build_object('school_name',sc.school_name,'city',sc.city,'state',sc.state) into school
  from show_registration_private.schools sc
  join public.entry_carts c on c.id=sc.cart_id
  join public.exhibitors e on e.id=sc.exhibitor_id and e.owner_user_id=c.user_id
  where sc.exhibitor_id=p_exhibitor_id and c.status='submitted'
    and exists(select 1 from show_registration_private.youth_exhibitors(c.id) y where y.exhibitor_id=p_exhibitor_id)
    and (c.show_id=p_show_id or exists (
      select 1 from show_addons_private.selections r
      where r.cart_id=c.id and r.show_id=p_show_id and r.exhibitor_id=p_exhibitor_id and r.kind='contest'
    ))
  order by sc.updated_at desc,c.submitted_at desc nulls last,c.id
  limit 1;
  return jsonb_build_object('applicable',true,'school',school);
end; $$;

create function public.get_exhibitor_school_for_show(p_show_id uuid, p_exhibitor_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select show_registration_private.exhibitor_school(p_show_id,p_exhibitor_id);
$$;
revoke all on function show_registration_private.exhibitor_school(uuid,uuid) from public,anon;
revoke all on function public.get_exhibitor_school_for_show(uuid,uuid) from public,anon;
grant execute on function show_registration_private.exhibitor_school(uuid,uuid) to authenticated;
grant execute on function public.get_exhibitor_school_for_show(uuid,uuid) to authenticated;
