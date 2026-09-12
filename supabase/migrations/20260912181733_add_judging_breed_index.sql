create schema if not exists judging_private;
revoke all on schema judging_private from public, anon;
grant usage on schema judging_private to authenticated, service_role;

-- The manual results landing page needs breed choices, not every hydrated
-- animal. Return one JSON value so the Data API row cap cannot hide choices.
create function judging_private.get_breed_index(p_show_id uuid, p_section_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' and (
    auth.uid() is null or (
      not coalesce(public.user_can_enter_results(p_show_id), false)
      and not coalesce(public.user_can_manage_entries(p_show_id), false)
      and not coalesce(public.user_can_manage_show_settings(p_show_id), false)
    )
  ) then
    raise exception 'You do not have access to this show' using errcode = '42501';
  end if;
  if p_section_id is null then
    raise exception 'A judging section is required' using errcode = '22023';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(b) order by b.breed_key), '[]'::jsonb)
    from (
      select lower(btrim(coalesce(e.breed, ''))) as breed_key,
        min(btrim(coalesce(e.breed, ''))) as breed,
        count(*) as entry_count,
        array_agg(distinct e.species::text order by e.species::text) as species
      from public.entries e
      where e.show_id = p_show_id and e.section_id = p_section_id
      -- Include scratches and fur rows, just like the judging reader.
      group by lower(btrim(coalesce(e.breed, '')))
    ) b
  );
end;
$$;
revoke all on function judging_private.get_breed_index(uuid,uuid) from public, anon;
grant execute on function judging_private.get_breed_index(uuid,uuid) to authenticated, service_role;

create or replace function public.get_judging_breed_index(p_show_id uuid, p_section_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select judging_private.get_breed_index(p_show_id, p_section_id);
$$;
revoke all on function public.get_judging_breed_index(uuid,uuid) from public, anon;
grant execute on function public.get_judging_breed_index(uuid,uuid) to authenticated, service_role;
notify pgrst, 'reload schema';
