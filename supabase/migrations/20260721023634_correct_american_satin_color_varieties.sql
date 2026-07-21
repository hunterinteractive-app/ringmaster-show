delete from public.cavy_sop_variety_order
where lower(breed_name) = 'american satin';

insert into public.cavy_sop_variety_order (
  breed_name,
  variety_name,
  breed_sort_order,
  variety_sort_order
)
values
  ('American Satin', 'Black', 40, 10),
  ('American Satin', 'Cream', 40, 20),
  ('American Satin', 'Orange', 40, 30),
  ('American Satin', 'Red', 40, 40),
  ('American Satin', 'White', 40, 50),
  ('American Satin', 'Any Other Self', 40, 60),
  ('American Satin', 'Agouti', 40, 70),
  ('American Satin', 'Intermixed Solids', 40, 80),
  ('American Satin', 'Ticked Solids', 40, 90),
  ('American Satin', 'Broken Colors & Tortoise Shell', 40, 100),
  ('American Satin', 'Any Other Marked', 40, 110),
  ('American Satin', 'Tan Pattern', 40, 120),
  ('American Satin', 'Cal Pattern', 40, 130);

with desired(name, sort_order) as (
  values
    ('Black', 1),
    ('Cream', 2),
    ('Orange', 3),
    ('Red', 4),
    ('White', 5),
    ('Any Other Self', 6),
    ('Agouti', 7),
    ('Intermixed Solids', 8),
    ('Ticked Solids', 9),
    ('Broken Colors & Tortoise Shell', 10),
    ('Any Other Marked', 11),
    ('Tan Pattern', 12),
    ('Cal Pattern', 13)
)
update public.varieties v
set is_active = true,
    sort_order = d.sort_order,
    group_id = null,
    updated_at = now()
from public.breeds b, desired d
where v.breed_id = b.id
  and b.species::text = 'cavy'
  and lower(b.name) = 'american satin'
  and lower(v.name) = lower(d.name);

with desired(name, sort_order) as (
  values
    ('Black', 1),
    ('Cream', 2),
    ('Orange', 3),
    ('Red', 4),
    ('White', 5),
    ('Any Other Self', 6),
    ('Agouti', 7),
    ('Intermixed Solids', 8),
    ('Ticked Solids', 9),
    ('Broken Colors & Tortoise Shell', 10),
    ('Any Other Marked', 11),
    ('Tan Pattern', 12),
    ('Cal Pattern', 13)
)
insert into public.varieties (breed_id, name, is_active, sort_order)
select b.id, d.name, true, d.sort_order
from public.breeds b
cross join desired d
where b.species::text = 'cavy'
  and lower(b.name) = 'american satin'
  and not exists (
    select 1
    from public.varieties v
    where v.breed_id = b.id
      and lower(v.name) = lower(d.name)
  );

update public.varieties v
set is_active = false,
    updated_at = now()
from public.breeds b
where v.breed_id = b.id
  and b.species::text = 'cavy'
  and lower(b.name) = 'american satin'
  and lower(v.name) in ('self', 'solid', 'marked');

do $migration$
declare
  v_updated integer := 0;
begin
  update public.entries e
  set variety = corrections.variety
  from (
    values
      ('2be480f7-3d61-4b0f-8471-b574bc9c0274'::uuid, 'Black'),
      ('96eff80a-6451-4dcb-8ebe-012234aa8191'::uuid, 'Black'),
      ('b76f011f-cfd4-4637-8044-497537903e45'::uuid, 'Black'),
      ('167c5261-de1a-4c75-8681-af2c61ae947e'::uuid, 'Black'),
      ('7b54b1b0-7257-4cdf-aced-8164d8753e1f'::uuid, 'Black'),
      ('a62d83c5-bdbd-469d-9bdb-1e41204815a4'::uuid, 'Black'),
      ('2fbe42c7-c915-4e30-82fb-5b4e7af873f0'::uuid, 'Any Other Marked'),
      ('5e3b0f74-8b3f-41bc-8779-c1d829390b07'::uuid, 'Any Other Marked'),
      ('f4692087-1df4-4560-bd65-2d0cc091a4ed'::uuid, 'Any Other Marked'),
      ('34b65883-4719-46c6-bfc2-42ddb01bcd77'::uuid, 'Any Other Marked'),
      ('6633dc18-91a7-46b4-b6bf-e83b60a73556'::uuid, 'Any Other Marked'),
      ('b8746128-e850-4560-876a-f82737f47430'::uuid, 'Any Other Marked'),
      ('513c8933-b65e-479f-ace6-a006ebdd641a'::uuid, 'Broken Colors & Tortoise Shell'),
      ('3bb908bf-036e-4108-a12f-fcde39fc6090'::uuid, 'Broken Colors & Tortoise Shell')
  ) as corrections(entry_id, variety)
  where e.id = corrections.entry_id
    and e.show_id = '0ebe76dd-7c19-4354-b605-dbb3fe964349'::uuid
    and e.species::text = 'cavy'
    and lower(btrim(e.breed)) = 'american satin'
    and e.variety is distinct from corrections.variety;

  get diagnostics v_updated = row_count;

  if v_updated > 0 then
    perform public.bump_show_results_version(
      '0ebe76dd-7c19-4354-b605-dbb3fe964349'::uuid
    );
  end if;
end;
$migration$;
