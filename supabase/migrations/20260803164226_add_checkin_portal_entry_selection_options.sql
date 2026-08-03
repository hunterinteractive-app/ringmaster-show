-- Token-scoped, effective show breed/variety options for the public check-in
-- portal. This uses the same show override rules as staff entry management.
create or replace function public.get_exhibitor_checkin_entry_selection_options(
  p_session_token text,
  p_entry_id uuid default null,
  p_breed_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_entry public.entries%rowtype;
  v_species text := 'rabbit';
  v_selected_breed_id uuid;
  v_selected_breed_name text;
  v_breeds jsonb := '[]'::jsonb;
  v_varieties jsonb := '[]'::jsonb;
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now();
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select * into v_settings
  from public.show_checkin_settings
  where show_id = v_session.show_id;
  if not found
     or not v_settings.is_enabled
     or (v_settings.opens_at is not null and now() < v_settings.opens_at)
     or (v_settings.closes_at is not null and now() > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;

  if p_entry_id is not null then
    select * into v_entry
    from public.entries
    where id = p_entry_id
      and show_id = v_session.show_id
      and exhibitor_id = v_session.exhibitor_id;
    if not found then
      raise exception 'Entry is not available for this check-in session';
    end if;
    v_species := case when lower(coalesce(v_entry.species, 'rabbit')) = 'cavy'
      then 'cavy' else 'rabbit' end;
  else
    select * into v_entry
    from public.entries
    where show_id = v_session.show_id
      and exhibitor_id = v_session.exhibitor_id
    order by updated_at desc nulls last
    limit 1;
    if found then
      v_species := case when lower(coalesce(v_entry.species, 'rabbit')) = 'cavy'
        then 'cavy' else 'rabbit' end;
    end if;
  end if;

  select coalesce(
    jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name) order by lower(b.name)),
    '[]'::jsonb
  ) into v_breeds
  from public.breeds b
  left join public.show_breeds sb
    on sb.show_id = v_session.show_id
   and sb.breed_id = b.id
  where b.species = v_species
    and b.is_active = true
    and coalesce(sb.is_enabled, true) = true;

  if p_breed_id is not null and exists (
    select 1
    from public.breeds b
    left join public.show_breeds sb
      on sb.show_id = v_session.show_id
     and sb.breed_id = b.id
    where b.id = p_breed_id
      and b.species = v_species
      and b.is_active = true
      and coalesce(sb.is_enabled, true) = true
  ) then
    v_selected_breed_id := p_breed_id;
  elsif v_entry.id is not null then
    select b.id into v_selected_breed_id
    from public.breeds b
    left join public.show_breeds sb
      on sb.show_id = v_session.show_id
     and sb.breed_id = b.id
    where b.species = v_species
      and b.is_active = true
      and coalesce(sb.is_enabled, true) = true
      and lower(btrim(b.name)) = lower(btrim(coalesce(v_entry.breed, '')))
    limit 1;
  end if;

  if v_selected_breed_id is not null then
    select b.name into v_selected_breed_name
    from public.breeds b
    where b.id = v_selected_breed_id;

    if v_species = 'cavy' then
      select coalesce(
        jsonb_agg(jsonb_build_object('id', 'cavy_' || lower(c.variety_name), 'name', c.variety_name)
          order by c.variety_sort_order, c.variety_name),
        '[]'::jsonb
      ) into v_varieties
      from public.cavy_sop_variety_order c
      where lower(btrim(c.breed_name)) = lower(btrim(v_selected_breed_name));
    elsif lower(v_selected_breed_name) like '%lop' then
      v_varieties := '[{"id":"lop_broken","name":"Broken"},{"id":"lop_solid","name":"Solid"}]'::jsonb;
    else
      select coalesce(
        jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name) order by lower(x.name)),
        '[]'::jsonb
      ) into v_varieties
      from (
        select v.id::text as id, v.name
        from public.varieties v
        left join public.show_varieties sv
          on sv.show_id = v_session.show_id
         and sv.breed_id = v_selected_breed_id
         and sv.variety_id = v.id
        where v.breed_id = v_selected_breed_id
          and v.is_active = true
          and coalesce(sv.is_enabled, true) = true
        union all
        select 'custom_' || sv.custom_name as id, sv.custom_name as name
        from public.show_varieties sv
        where sv.show_id = v_session.show_id
          and sv.breed_id = v_selected_breed_id
          and sv.variety_id is null
          and sv.is_enabled = true
          and nullif(btrim(sv.custom_name), '') is not null
      ) x;
    end if;
  end if;

  return jsonb_build_object(
    'species', v_species,
    'selected_breed_id', v_selected_breed_id,
    'breeds', v_breeds,
    'varieties', v_varieties
  );
end;
$$;

revoke all on function public.get_exhibitor_checkin_entry_selection_options(text, uuid, uuid) from public;
grant execute on function public.get_exhibitor_checkin_entry_selection_options(text, uuid, uuid)
  to anon, authenticated, service_role;
