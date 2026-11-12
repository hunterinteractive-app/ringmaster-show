-- Prevent stale clients and direct entry edits from assigning six-class ages
-- to four-class rabbits. Commercial classes and cavy classes are unaffected.
create or replace function public.validate_entry_intermediate_class()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_class_system text;
begin
  if lower(btrim(coalesce(new.species::text, ''))) <> 'rabbit'
     or lower(btrim(coalesce(new.class_name, ''))) <> 'intermediate' then
    return new;
  end if;

  select coalesce(nullif(btrim(sb.class_system_override::text), ''), b.class_system::text, 'four')
    into v_class_system
  from public.breeds b
  left join public.show_breeds sb on sb.breed_id = b.id and sb.show_id = new.show_id
  where b.species = 'rabbit'
    and lower(btrim(regexp_replace(b.name, '\s*\(COD\)$', '', 'i'))) =
        lower(btrim(regexp_replace(coalesce(new.breed, ''), '\s*\(COD\)$', '', 'i')))
    and (b.local_show_id is null or b.local_show_id = new.show_id)
  order by (b.local_show_id = new.show_id) desc nulls last, b.id
  limit 1;

  if found and regexp_replace(lower(v_class_system), '[^a-z0-9]', '', 'g')
      not in ('six', 'sixclass', '6', '6class') then
    raise exception '% is a four-class breed. Select Junior or Senior (or Pre-Junior where offered).', new.breed
      using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_entry_intermediate_class() from public;
create trigger validate_entry_intermediate_class
before insert or update of show_id, species, breed, class_name on public.entries
for each row execute function public.validate_entry_intermediate_class();
