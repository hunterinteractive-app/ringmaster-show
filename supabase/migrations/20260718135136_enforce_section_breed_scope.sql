create or replace function public.section_allows_breed(
  p_section_id uuid,
  p_breed text,
  p_species text default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when ss.id is null then false
    when lower(btrim(coalesce(ss.breed_scope, 'all'))) in ('all', 'all_breed', 'meat_only') then true
    when nullif(btrim(coalesce(p_breed, '')), '') is null then false
    when lower(btrim(coalesce(ss.breed_scope, 'all'))) in ('single', 'limited') then exists (
      select 1
      from public.breeds b
      where b.id = any(coalesce(ss.allowed_breed_ids, array[]::uuid[]))
        and lower(btrim(b.name)) = lower(btrim(p_breed))
        and (
          nullif(btrim(coalesce(p_species, '')), '') is null
          or lower(btrim(b.species::text)) = lower(btrim(p_species))
        )
    )
    else false
  end
  from public.show_sections ss
  where ss.id = p_section_id;
$$;

create or replace function public.enforce_entry_section_breed_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_section_show_id uuid;
  v_section_label text;
begin
  if new.section_id is null then
    return new;
  end if;

  select ss.show_id,
         coalesce(nullif(btrim(ss.display_name), ''),
                  concat(initcap(ss.kind::text), ' ', upper(ss.letter)))
    into v_section_show_id, v_section_label
  from public.show_sections ss
  where ss.id = new.section_id;

  if v_section_show_id is null then
    raise exception 'The selected show section no longer exists.';
  end if;
  if v_section_show_id is distinct from new.show_id then
    raise exception 'The selected show section belongs to a different show.';
  end if;
  if not public.section_allows_breed(new.section_id, new.breed, new.species) then
    raise exception '% is not an allowed breed for %.',
      coalesce(nullif(btrim(new.breed), ''), 'This animal'), v_section_label;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_entry_section_breed_scope on public.entries;
create trigger enforce_entry_section_breed_scope
before insert or update of show_id, section_id, breed, species
on public.entries
for each row execute function public.enforce_entry_section_breed_scope();

create or replace function public.enforce_cart_item_section_breed_scope()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_cart_show_id uuid;
  v_section_show_id uuid;
  v_section_label text;
begin
  select c.show_id into v_cart_show_id
  from public.entry_carts c where c.id = new.cart_id;

  select ss.show_id,
         coalesce(nullif(btrim(ss.display_name), ''),
                  concat(initcap(ss.kind::text), ' ', upper(ss.letter)))
    into v_section_show_id, v_section_label
  from public.show_sections ss where ss.id = new.section_id;

  if v_cart_show_id is null then
    raise exception 'The selected entry cart no longer exists.';
  end if;
  if v_section_show_id is null then
    raise exception 'The selected show section no longer exists.';
  end if;
  if v_cart_show_id is distinct from v_section_show_id then
    raise exception 'The selected show section belongs to a different show.';
  end if;
  if not public.section_allows_breed(new.section_id, new.breed, new.species) then
    raise exception '% is not an allowed breed for %.',
      coalesce(nullif(btrim(new.breed), ''), 'This animal'), v_section_label;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_cart_item_section_breed_scope on public.entry_cart_items;
create trigger enforce_cart_item_section_breed_scope
before insert or update of cart_id, section_id, breed, species
on public.entry_cart_items
for each row execute function public.enforce_cart_item_section_breed_scope();

revoke all on function public.section_allows_breed(uuid, text, text) from public;
grant execute on function public.section_allows_breed(uuid, text, text) to authenticated, service_role;

comment on function public.section_allows_breed(uuid, text, text) is
  'Canonical validation for show-section single/limited breed scope.';
