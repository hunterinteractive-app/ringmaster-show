-- Netherland Dwarf colors are classed together under one Tortoise Shell
-- variety. Preserve the existing Black variety; only consolidate
-- incorrectly prefixed tortoise labels.
--
-- This is a one-time historical data correction, including entries in locked
-- shows. Keep the normal application lock guard enabled immediately afterward.
alter table public.entries
  disable trigger prevent_entry_changes_when_locked;

do $migration$
declare
  v_breed_id uuid;
  v_canonical_variety_id uuid;
begin
  select id
  into v_breed_id
  from public.breeds
  where lower(name) = lower('Netherland Dwarf')
    and species = 'rabbit'
  order by id
  limit 1;

  if v_breed_id is null then
    raise exception 'Netherland Dwarf rabbit breed was not found';
  end if;

  select id
  into v_canonical_variety_id
  from public.varieties
  where breed_id = v_breed_id
    and lower(name) = lower('Tortoise Shell')
  order by id
  limit 1;

  if v_canonical_variety_id is null then
    select id
    into v_canonical_variety_id
    from public.varieties
    where breed_id = v_breed_id
      and lower(name) = lower('Black Tortoise Shell')
    order by id
    limit 1;

    if v_canonical_variety_id is null then
      raise exception 'No Netherland Dwarf tortoise variety was found to normalize';
    end if;

    update public.varieties
    set name = 'Tortoise Shell',
        is_active = true,
        updated_at = now()
    where id = v_canonical_variety_id;
  end if;

  -- Retain obsolete catalog rows for audit/history, but prevent every entry
  -- surface from offering them as new choices.
  update public.varieties
  set is_active = false,
      updated_at = now()
  where breed_id = v_breed_id
    and id <> v_canonical_variety_id
    and lower(btrim(name)) like '% tortoise shell';

  update public.show_varieties
  set is_enabled = false
  where breed_id = v_breed_id
    and variety_id in (
      select id
      from public.varieties
      where breed_id = v_breed_id
        and id <> v_canonical_variety_id
        and lower(btrim(name)) like '% tortoise shell'
    );

  update public.animals
  set variety = 'Tortoise Shell'
  where lower(breed) = lower('Netherland Dwarf')
    and lower(btrim(variety)) like '% tortoise shell';

  update public.entries
  set variety = 'Tortoise Shell'
  where lower(breed) = lower('Netherland Dwarf')
    and lower(btrim(variety)) like '% tortoise shell';

  update public.entry_cart_items
  set variety = 'Tortoise Shell'
  where lower(breed) = lower('Netherland Dwarf')
    and lower(btrim(variety)) like '% tortoise shell';

  update public.show_results_raw
  set variety_name = 'Tortoise Shell'
  where lower(breed_name) = lower('Netherland Dwarf')
    and lower(btrim(variety_name)) like '% tortoise shell';

  update public.show_special_money_rules
  set variety_name = 'Tortoise Shell'
  where lower(breed_name) = lower('Netherland Dwarf')
    and lower(btrim(variety_name)) like '% tortoise shell';

  update public.sweepstakes_entry_results
  set variety_name = 'Tortoise Shell'
  where lower(breed_name) = lower('Netherland Dwarf')
    and lower(btrim(variety_name)) like '% tortoise shell';
end
$migration$;

alter table public.entries
  enable trigger prevent_entry_changes_when_locked;
