-- Netherland Dwarf is a four-class breed and does not offer Pre-Junior.
-- Correct the historical HC77 records (and any equivalent rows) while also
-- preventing entry writers from saving Pre-Junior for breeds that disable it.
alter table public.entries
  disable trigger prevent_entry_changes_when_locked;

update public.entries
set class_name = 'Junior',
    updated_at = now()
where lower(btrim(breed)) = lower('Netherland Dwarf')
  and regexp_replace(lower(coalesce(class_name, '')), '[^a-z]', '', 'g') = 'prejunior';

update public.entry_cart_items
set class_name = 'Junior'
where lower(btrim(breed)) = lower('Netherland Dwarf')
  and regexp_replace(lower(coalesce(class_name, '')), '[^a-z]', '', 'g') = 'prejunior';

update public.show_results_raw
set class_name = 'Junior'
where lower(btrim(breed_name)) = lower('Netherland Dwarf')
  and regexp_replace(lower(coalesce(class_name, '')), '[^a-z]', '', 'g') = 'prejunior';

update public.sweepstakes_entry_results
set class_name = 'Junior'
where lower(btrim(breed_name)) = lower('Netherland Dwarf')
  and regexp_replace(lower(coalesce(class_name, '')), '[^a-z]', '', 'g') = 'prejunior';

alter table public.entries
  enable trigger prevent_entry_changes_when_locked;

create or replace function public.validate_entry_prejunior_class()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_has_prejunior boolean;
begin
  if lower(btrim(coalesce(new.species::text, ''))) <> 'rabbit'
     or regexp_replace(lower(coalesce(new.class_name, '')), '[^a-z]', '', 'g') <> 'prejunior' then
    return new;
  end if;

  select coalesce(b.has_prejunior, false)
  into v_has_prejunior
  from public.breeds b
  where b.species = 'rabbit'
    and b.is_active = true
    and lower(btrim(b.name)) = lower(btrim(coalesce(new.breed, '')))
    and (b.local_show_id is null or b.local_show_id = new.show_id)
  order by (b.local_show_id = new.show_id) desc nulls last, b.id
  limit 1;

  if found and not v_has_prejunior then
    raise exception '% does not offer a Pre-Junior class.', new.breed
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_entry_prejunior_class on public.entries;
create trigger validate_entry_prejunior_class
before insert or update of show_id, species, breed, class_name on public.entries
for each row execute function public.validate_entry_prejunior_class();

-- The public check-in portal is token-scoped, so expose only the class
-- metadata for a breed available to the active check-in session.
create or replace function public.get_exhibitor_checkin_breed_class_metadata(
  p_session_token text,
  p_breed_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_class_system text;
  v_has_prejunior boolean;
begin
  select *
  into v_session
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

  select coalesce(
           nullif(btrim(sb.class_system_override::text), ''),
           b.class_system::text,
           'four'
         ),
         coalesce(b.has_prejunior, false)
  into v_class_system, v_has_prejunior
  from public.breeds b
  left join public.show_breeds sb
    on sb.show_id = v_session.show_id
   and sb.breed_id = b.id
  where b.id = p_breed_id
    and b.is_active = true
    and (b.local_show_id is null or b.local_show_id = v_session.show_id)
    and coalesce(sb.is_enabled, true) = true
  limit 1;

  if not found then
    raise exception 'Breed is not available for this show.'
      using errcode = '22023';
  end if;

  return jsonb_build_object(
    'class_system', coalesce(v_class_system, 'four'),
    'has_prejunior', v_has_prejunior
  );
end;
$$;

revoke all on function public.get_exhibitor_checkin_breed_class_metadata(text, uuid)
  from public;
grant execute on function public.get_exhibitor_checkin_breed_class_metadata(text, uuid)
  to anon, authenticated, service_role;
