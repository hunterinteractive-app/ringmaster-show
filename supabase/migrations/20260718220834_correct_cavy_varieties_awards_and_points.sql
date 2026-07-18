-- Cavy awards are judged by variety, not by rabbit-style groups. Preserve the
-- historical BOG/BOSG aliases in application/database normalization, while
-- making BOV/BOSV the canonical codes for all new cavy results.

delete from public.cavy_sop_variety_order
where lower(breed_name) = 'american satin';

insert into public.cavy_sop_variety_order (
  breed_name,
  variety_name,
  breed_sort_order,
  variety_sort_order
)
values
  ('American Satin', 'Self', 40, 10),
  ('American Satin', 'Agouti', 40, 20),
  ('American Satin', 'Solid', 40, 30),
  ('American Satin', 'Marked', 40, 40),
  ('American Satin', 'Tan Pattern', 40, 50),
  ('American Satin', 'Cal Pattern', 40, 60);

update public.breeds
set uses_group_awards = false,
    uses_variety_awards = true
where species::text = 'cavy';

alter table public.point_award_scale
  add column if not exists cavy_award_points numeric;

insert into public.point_award_scale (
  award_code,
  source_type,
  award_points,
  cavy_award_points,
  is_active,
  sort_order
)
values
  ('BJV', 'variety_award', 0, 10, true, 11),
  ('BIV', 'variety_award', 0, 10, true, 12),
  ('BSV', 'variety_award', 0, 10, true, 13),
  ('BJB', 'breed_award', 0, 25, true, 51),
  ('BIB', 'breed_award', 0, 25, true, 52),
  ('BSB', 'breed_award', 0, 25, true, 53)
on conflict (award_code) do update
set source_type = excluded.source_type,
    cavy_award_points = excluded.cavy_award_points,
    is_active = excluded.is_active,
    sort_order = excluded.sort_order,
    updated_at = now();

update public.point_award_scale
set cavy_award_points = case award_code
      when 'BOV' then 25
      when 'BOSV' then 15
      when 'BOB' then 50
      when 'BOSB' then 25
      when 'BIS' then 50
      when 'RIS' then 25
      when 'BRIS' then 25
      else cavy_award_points
    end,
    updated_at = now()
where award_code in ('BOV', 'BOSV', 'BOB', 'BOSB', 'BIS', 'RIS', 'BRIS');

create or replace function public.generate_show_award_points_entries(
  p_show_id uuid,
  p_finalize_run_id uuid
)
returns integer
language plpgsql
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
  insert into public.show_points_entries (
    show_id, finalize_run_id, exhibitor_id, animal_id, breed_id, variety_id,
    group_id, class_key, points_category, source_type, placement, class_size,
    base_points, multiplier, total_points, qualified, qualification_note,
    source_result_id, metadata
  )
  with awards_union as (
    select ea.show_id, ea.entry_id, ea.award_code, null::uuid as result_id
    from public.entry_awards ea
    where ea.show_id = p_show_id
    union all
    select r.show_id, r.entry_id, r.award, r.id as result_id
    from public.results r
    where r.show_id = p_show_id
      and r.award is not null
      and btrim(r.award) <> ''
    union all
    select e.show_id, e.id, e.special_awards, null::uuid
    from public.entries e
    where e.show_id = p_show_id
      and e.special_awards is not null
      and btrim(e.special_awards) <> ''
  ),
  normalized as (
    select distinct
      au.show_id,
      au.entry_id,
      upper(btrim(au.award_code)) as stored_award_code,
      au.result_id
    from awards_union au
    where au.award_code is not null
      and btrim(au.award_code) <> ''
  ),
  entries_with_awards as (
    select
      n.show_id,
      n.entry_id,
      n.result_id,
      e.exhibitor_id,
      e.animal_id,
      e.species,
      e.class_name,
      e.scratched_at,
      e.is_shown,
      e.is_disqualified,
      e.breed,
      e.variety,
      case
        when e.species::text = 'cavy' then
          case n.stored_award_code
            when 'BOG' then 'BOV'
            when 'BEST OF GROUP' then 'BOV'
            when 'BOSG' then 'BOSV'
            when 'BEST OPPOSITE SEX OF GROUP' then 'BOSV'
            when 'BEST JUNIOR' then 'BJV'
            when 'BEST INTERMEDIATE' then 'BIV'
            when 'BEST SENIOR' then 'BSV'
            when 'BEST IN SHOW' then 'BIS'
            when 'RESERVE IN SHOW' then 'RIS'
            else n.stored_award_code
          end
        else n.stored_award_code
      end as award_code
    from normalized n
    join public.entries e
      on e.id = n.entry_id
     and e.show_id = n.show_id
  ),
  joined as (
    select
      x.show_id,
      x.entry_id,
      x.exhibitor_id,
      x.animal_id,
      x.species,
      x.class_name,
      x.scratched_at,
      coalesce(x.is_shown, true) as is_shown,
      coalesce(x.is_disqualified, false) as is_disqualified,
      b.id as breed_id,
      v.id as variety_id,
      g.id as group_id,
      x.award_code,
      x.result_id,
      case when x.species::text = 'cavy'
        then 'cavy'::points_category
        else 'rabbit'::points_category
      end as points_category,
      pas.source_type,
      case when x.species::text = 'cavy'
        then coalesce(pas.cavy_award_points, 0)
        else pas.award_points
      end as award_points
    from entries_with_awards x
    join public.point_award_scale pas
      on pas.award_code = x.award_code
     and pas.is_active = true
    left join public.breeds b
      on lower(b.name) = lower(x.breed)
     and b.species = x.species
    left join public.varieties v
      on lower(v.name) = lower(x.variety)
     and v.breed_id = b.id
    left join public.groups g
      on g.breed_id = b.id
     and exists (
       select 1 from public.group_varieties gv
       where gv.group_id = g.id and gv.variety_id = v.id
     )
  )
  select
    show_id,
    p_finalize_run_id,
    exhibitor_id,
    animal_id,
    breed_id,
    variety_id,
    group_id,
    class_name,
    points_category,
    source_type,
    null,
    null,
    case when scratched_at is not null or not is_shown or is_disqualified
      then 0 else award_points end,
    1,
    case when scratched_at is not null or not is_shown or is_disqualified
      then 0 else award_points end,
    scratched_at is null and is_shown and not is_disqualified,
    case
      when scratched_at is not null then 'Scratched'
      when not is_shown then 'Not shown'
      when is_disqualified then 'Disqualified'
      else null
    end,
    result_id,
    jsonb_build_object('entry_id', entry_id, 'award_code', award_code)
  from joined;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;
