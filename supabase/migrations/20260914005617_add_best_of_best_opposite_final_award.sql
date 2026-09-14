-- Reuse the existing secretary allowlist. No global-admin bypass: eligibility
-- follows the show's creator, owner, or explicitly assigned show secretary.
insert into public.secretary_feature_access(feature_key, user_id)
select 'best_of_best_opposite', id from auth.users
where id = '3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'::uuid
on conflict (feature_key, user_id) do nothing;

create schema if not exists show_awards_private;
revoke all on schema show_awards_private from public, anon;
grant usage on schema show_awards_private to authenticated, service_role;

-- The private lookup can read the allowlisted secretary even when another
-- authorized show worker is signed in. The public wrapper never exposes IDs.
create function show_awards_private.can_configure_best_opposite(p_show_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null
    and public.user_can_manage_show_settings(p_show_id)
    and exists (
      select 1 from public.shows s
      join public.secretary_feature_access a
        on a.feature_key = 'best_of_best_opposite'
      where s.id = p_show_id and (
        a.user_id = s.created_by or a.user_id = s.owner_user_id
        or exists (select 1 from public.show_admins sa
          where sa.show_id = s.id and sa.user_id = a.user_id)
        or exists (select 1 from public.role_assignments ra
          where ra.show_id = s.id and ra.user_id = a.user_id
            and ra.role::text = 'admin')
        or exists (select 1 from public.show_role_assignments ra
          where ra.show_id = s.id and ra.user_id = a.user_id
            and ra.role = 'show_admin')
      )
    );
$$;
revoke all on function show_awards_private.can_configure_best_opposite(uuid)
  from public, anon;
grant execute on function show_awards_private.can_configure_best_opposite(uuid)
  to authenticated, service_role;

create function public.can_configure_best_opposite_final_award(p_show_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select show_awards_private.can_configure_best_opposite(p_show_id);
$$;
revoke all on function public.can_configure_best_opposite_final_award(uuid)
  from public, anon;
grant execute on function public.can_configure_best_opposite_final_award(uuid)
  to authenticated, service_role;

alter table public.shows drop constraint if exists shows_final_award_mode_check;
alter table public.shows add constraint shows_final_award_mode_check
  check (final_award_mode in
    ('four_six_bis', 'bis_ris', 'bis_1ris_2ris', 'bis_1ris_2ris_bbos'));

create function show_awards_private.guard_final_award_mode()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.final_award_mode = 'bis_1ris_2ris_bbos'
      and new.final_award_mode is distinct from old.final_award_mode
      and exists (select 1 from public.entry_awards
        where show_id = new.id and regexp_replace(lower(award_code), '[^a-z0-9]+', '', 'g')
          in ('bbos', 'bestofthebestopposite')) then
    raise exception 'Remove Best of the Best Opposite awards before changing the final award format.';
  end if;
  if new.final_award_mode <> 'bis_1ris_2ris_bbos' then return new; end if;
  if tg_op = 'UPDATE' and new.final_award_mode = old.final_award_mode then
    return new;
  end if;
  -- Service jobs retain their normal access. Interactive selection must use an
  -- existing show (creation uses the ordinary format) with an eligible secretary.
  if current_user = 'service_role' or
      coalesce(auth.jwt()->>'role', '') = 'service_role' then return new; end if;
  if not public.can_configure_best_opposite_final_award(new.id) then
    raise exception 'This final award format is only available for selected secretaries’ shows.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function show_awards_private.guard_final_award_mode()
  from public, anon, authenticated;
create trigger guard_best_opposite_final_award_mode
before insert or update of final_award_mode on public.shows
for each row execute function show_awards_private.guard_final_award_mode();

-- Deferred checks see the whole result save, including BOS and BBOS inserted in
-- either order. They also reject leaving BBOS behind after removing BOS or
-- changing the entry to an ineligible result. Existing awards are unaffected.
create function show_awards_private.validate_best_opposite_entry()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
  v_entry_id uuid;
  v_entry public.entries%rowtype;
  v_mode text;
  v_species text;
  v_count integer;
begin
  if tg_table_name = 'entry_awards' then
    -- Most awards do not participate in this rule; avoid any table reads.
    if tg_op = 'INSERT' and regexp_replace(lower(new.award_code), '[^a-z0-9]+', '', 'g')
        not in ('bbos', 'bestofthebestopposite', 'bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed') then
      return null;
    elsif tg_op = 'DELETE' and regexp_replace(lower(old.award_code), '[^a-z0-9]+', '', 'g')
        not in ('bbos', 'bestofthebestopposite', 'bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed') then
      return null;
    elsif tg_op = 'UPDATE' and regexp_replace(lower(new.award_code), '[^a-z0-9]+', '', 'g')
        not in ('bbos', 'bestofthebestopposite', 'bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed')
        and regexp_replace(lower(old.award_code), '[^a-z0-9]+', '', 'g')
        not in ('bbos', 'bestofthebestopposite', 'bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed') then
      return null;
    end if;
    if tg_op = 'UPDATE' and old.entry_id <> new.entry_id then
      -- Moving an award between entries is never needed by Results Entry.
      if regexp_replace(lower(old.award_code), '[^a-z0-9]+', '', 'g') in ('bbos', 'bestofthebestopposite', 'bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed') then
        raise exception 'Remove the award before moving it to another entry.';
      end if;
    end if;
    v_entry_id := case when tg_op = 'DELETE' then old.entry_id else new.entry_id end;
  else
    v_entry_id := new.id;
  end if;
  select * into v_entry from public.entries where id = v_entry_id;
  if not found then return null; end if;
  if not exists (select 1 from public.entry_awards
      where entry_id = v_entry_id and regexp_replace(lower(award_code), '[^a-z0-9]+', '', 'g') in ('bbos', 'bestofthebestopposite')) then
    return null;
  end if;
  if coalesce(auth.jwt()->>'role', '') <> 'service_role'
      and not (session_user = 'postgres' and auth.uid() is null)
      and (auth.uid() is null or not public.user_can_enter_results(v_entry.show_id)) then
    raise exception 'You do not have permission to enter results for this show.' using errcode = '42501';
  end if;
  select final_award_mode into v_mode from public.shows where id = v_entry.show_id;
  if v_mode is distinct from 'bis_1ris_2ris_bbos' then
    raise exception 'Best of the Best Opposite requires its final award format.';
  end if;
  if v_entry.section_id is null or coalesce(v_entry.is_fur, false)
      or v_entry.scratched_at is not null or not coalesce(v_entry.is_shown, true)
      or coalesce(v_entry.is_disqualified, false)
      or lower(trim(coalesce(v_entry.result_status, 'Shown'))) in ('no show', 'unworthy of award')
      or lower(trim(coalesce(v_entry.result_status, ''))) like 'disqualified%'
      or coalesce(nullif(trim(v_entry.placement::text), ''), '') <> '1' then
    raise exception 'Best of the Best Opposite requires an eligible first-place rabbit or cavy.';
  end if;
  if not exists (select 1 from public.entry_awards
      where entry_id = v_entry_id and show_id = v_entry.show_id
        and regexp_replace(lower(award_code), '[^a-z0-9]+', '', 'g')
          in ('bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed')) then
    raise exception 'Best of the Best Opposite requires Best Opposite Sex of Breed (BOS) first.';
  end if;
  if exists (select 1 from public.entry_awards where entry_id = v_entry_id
      and regexp_replace(lower(award_code), '[^a-z0-9]+', '', 'g') in ('bbos', 'bestofthebestopposite') and show_id <> v_entry.show_id) then
    raise exception 'Award and entry must belong to the same show.';
  end if;
  v_species := case when lower(trim(coalesce(v_entry.species::text, ''))) = 'cavy'
    or lower(trim(coalesce(v_entry.sex, ''))) in ('boar', 'sow') then 'cavy' else 'rabbit' end;
  perform pg_advisory_xact_lock(hashtextextended(
    'BBOS:' || v_entry.show_id::text || ':' || v_entry.section_id::text || ':' || v_species, 0));
  select count(distinct e.id) into v_count from public.entries e
  join public.entry_awards a on a.entry_id = e.id
  where e.show_id = v_entry.show_id and e.section_id = v_entry.section_id
    and regexp_replace(lower(a.award_code), '[^a-z0-9]+', '', 'g') in ('bbos', 'bestofthebestopposite')
    and (case when lower(trim(coalesce(e.species::text, ''))) = 'cavy'
      or lower(trim(coalesce(e.sex, ''))) in ('boar', 'sow') then 'cavy' else 'rabbit' end) = v_species;
  if v_count > 1 then
    raise exception 'Best of the Best Opposite is already assigned for this species in this section.';
  end if;
  return null;
end;
$$;
revoke all on function show_awards_private.validate_best_opposite_entry()
  from public, anon, authenticated;
create constraint trigger validate_best_opposite_awards
  after insert or update or delete on public.entry_awards
  deferrable initially deferred for each row
  execute function show_awards_private.validate_best_opposite_entry();
create constraint trigger validate_best_opposite_result
  after update on public.entries
  deferrable initially deferred for each row
  when (old.section_id is distinct from new.section_id
    or old.show_id is distinct from new.show_id
    or old.species is distinct from new.species or old.sex is distinct from new.sex
    or old.placement is distinct from new.placement
    or old.is_shown is distinct from new.is_shown
    or old.is_disqualified is distinct from new.is_disqualified
    or old.result_status is distinct from new.result_status
    or old.is_fur is distinct from new.is_fur
    or old.scratched_at is distinct from new.scratched_at)
  execute function show_awards_private.validate_best_opposite_entry();

-- Restore one canonical closeout readiness validator for every final-award
-- mode used by Results Entry. This also preserves placement 0 as an entered,
-- unplaced result that must not form a duplicate-placement group.
create or replace function public.show_results_readiness_scoped(
  p_show_id uuid,
  p_section_ids uuid[]
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
with show_settings as (
  select lower(trim(coalesce(s.final_award_mode, 'four_six_bis'))) as final_award_mode
  from public.shows s where s.id = p_show_id
),
eligible_rows as (
  select e.id as entry_id, e.section_id,
    case
      when lower(trim(coalesce(e.species::text, ''))) = 'cavy'
        or lower(trim(coalesce(e.sex, ''))) in ('boar', 'sow') then 'cavy'
      else 'rabbit'
    end as species_key,
    coalesce(e.is_shown, true) as is_shown, coalesce(e.is_disqualified, false) as is_disqualified,
    coalesce(e.is_fur, false) as is_fur_key, e.scratched_at,
    lower(trim(coalesce(e.result_status, 'Shown'))) as result_status_key,
    nullif(trim(case when coalesce(e.is_fur, false) then e.fur_placement::text else e.placement::text end), '') as placement,
    e.judged_by_show_judge_id,
    lower(trim(coalesce(nullif(e.breed, ''), ''))) as breed_key,
    lower(trim(coalesce(nullif(e.variety, ''), ''))) as variety_key,
    lower(trim(coalesce(e.class_name, ''))) as class_name_key,
    lower(trim(coalesce(e.sex, ''))) as sex_key
  from public.entries e
  where e.show_id = p_show_id and e.section_id = any(coalesce(p_section_ids, array[]::uuid[]))
),
required_results as (
  select * from eligible_rows
  where scratched_at is null and is_shown = true and is_disqualified = false
    and result_status_key not in ('no show', 'unworthy of award')
    and result_status_key not like 'disqualified%'
),
required_entries as (
  select distinct entry_id, section_id, species_key, breed_key from required_results
),
missing_placement as (
  select count(distinct entry_id)::int as total from required_results where placement is null
),
missing_judge as (
  select count(distinct entry_id)::int as total from required_results where judged_by_show_judge_id is null
),
duplicate_placement_groups as (
  select count(*)::int as total from (
    select section_id, breed_key, variety_key, class_name_key, sex_key, is_fur_key, placement
    from required_results where placement is not null and placement <> '0'
    group by section_id, breed_key, variety_key, class_name_key, sex_key, is_fur_key, placement
    having count(distinct entry_id) > 1
  ) duplicates
),
applicable_final_award_sections as (
  select distinct re.section_id, re.species_key,
    coalesce(nullif(trim(sec.display_name), ''), initcap(sec.kind::text) || ' ' || upper(sec.letter)) as section_label,
    sec.sort_order
  from required_entries re
  join public.show_sections sec on sec.id = re.section_id
  cross join show_settings ss
  where ss.final_award_mode in ('four_six_bis', 'bis_ris', 'bis_1ris_2ris', 'bis_1ris_2ris_bbos')
    and (ss.final_award_mode <> 'four_six_bis' or re.species_key = 'rabbit')
),
normalized_final_awards as (
  select distinct re.entry_id, re.section_id, re.species_key,
    case
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('bob', 'bestofbreed') then 'BOB'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('b4c', 'best4class', 'bestfourclass') then 'B4C'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('b6c', 'best6class', 'bestsixclass') then 'B6C'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('bis', 'bestinshow', 'bestinshowrabbit') then 'BIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('ris', 'reserveinshow') then 'RIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('1ris', '1stris', 'firstris', '1streserveinshow', 'firstreserveinshow') then '1RIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('2ris', '2ndris', 'secondris', '2ndreserveinshow', 'secondreserveinshow') then '2RIS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('bbos', 'bestofthebestopposite') then 'BBOS'
      when regexp_replace(lower(coalesce(ea.award_code, '')), '[^a-z0-9]+', '', 'g') in ('bos', 'bosb', 'bestoppositesexofbreed', 'bestoppositeofbreed') then 'BOSB'
      else null
    end as award_kind
  from required_entries re join public.entry_awards ea on ea.entry_id = re.entry_id
),
final_awards as (
  select nfa.* from normalized_final_awards nfa cross join show_settings ss
  where nfa.award_kind is not null and (
    (ss.final_award_mode = 'four_six_bis' and nfa.award_kind in ('BOB', 'B4C', 'B6C', 'BIS')) or
    (ss.final_award_mode = 'bis_ris' and nfa.award_kind in ('BOB', 'BIS', 'RIS')) or
    (ss.final_award_mode in ('bis_1ris_2ris', 'bis_1ris_2ris_bbos') and nfa.award_kind in ('BIS', '1RIS', '2RIS')) or
    (ss.final_award_mode = 'bis_1ris_2ris_bbos' and nfa.award_kind in ('BOSB', 'BBOS'))
  )
),
bob_awards as (
  select distinct section_id, species_key, entry_id
  from final_awards
  where award_kind = 'BOB'
),
breed_classified_bobs as (
  select distinct fa.section_id, fa.species_key, fa.entry_id,
    case when lower(trim(coalesce(sb.class_system_override, b.class_system, 'four'))) in ('six', 'sixclass', 'six_class', 'six-class', '6') then 'six' else 'four' end as class_system
  from bob_awards fa
  join required_entries re on re.entry_id = fa.entry_id
  join public.breeds b on lower(trim(b.name)) = re.breed_key and lower(trim(b.species::text)) = 'rabbit'
  left join public.show_breeds sb on sb.show_id = p_show_id and sb.breed_id = b.id
  where fa.species_key = 'rabbit'
),
invalid_final_award_rows as (
  select
    fa.section_id,
    fa.species_key,
    coalesce(nullif(trim(sec.display_name), ''), initcap(sec.kind::text) || ' ' || upper(sec.letter)) as section_label,
    sec.sort_order as section_sort_order,
    fa.award_kind as award_code,
    case fa.award_kind
      when 'B4C' then 'Best 4-Class'
      when 'B6C' then 'Best 6-Class'
      when 'BIS' then 'Best in Show'
      when 'RIS' then 'Reserve in Show'
      when 'BBOS' then 'Best of the Best Opposite'
      else fa.award_kind
    end as award_label,
    case
      when fa.award_kind = 'BBOS' then
        'Best of the Best Opposite must be awarded to a Best Opposite Sex of Breed (BOS) winner.'
      when fa.award_kind = 'B4C' then
        'Best 4-Class must be awarded to Best of Breed from a four-class rabbit breed.'
      when fa.award_kind = 'B6C' then
        'Best 6-Class must be awarded to Best of Breed from a six-class rabbit breed.'
      when ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'BIS' then
        'Best in Show must be selected from the Best 4-Class or Best 6-Class winner.'
      when ss.final_award_mode = 'bis_ris' and fa.award_kind = 'BIS' then
        'Best in Show must be awarded to a Best of Breed winner.'
      when ss.final_award_mode = 'bis_ris' and fa.award_kind = 'RIS' then
        'Reserve in Show must be awarded to a Best of Breed winner.'
    end as reason
  from final_awards fa
  join public.show_sections sec on sec.id = fa.section_id
  cross join show_settings ss
  where
    (fa.award_kind = 'BBOS' and not exists (
      select 1 from final_awards qualifier
      where qualifier.entry_id = fa.entry_id and qualifier.award_kind = 'BOSB'
    )) or
    (ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'B4C' and not exists (
      select 1 from breed_classified_bobs bob
      where bob.section_id = fa.section_id
        and bob.species_key = fa.species_key
        and bob.entry_id = fa.entry_id
        and bob.class_system = 'four'
    ))
    or
    (ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'B6C' and not exists (
      select 1 from breed_classified_bobs bob
      where bob.section_id = fa.section_id
        and bob.species_key = fa.species_key
        and bob.entry_id = fa.entry_id
        and bob.class_system = 'six'
    ))
    or
    (ss.final_award_mode = 'four_six_bis' and fa.award_kind = 'BIS' and not exists (
      select 1 from final_awards qualifier
      where qualifier.section_id = fa.section_id
        and qualifier.species_key = fa.species_key
        and qualifier.entry_id = fa.entry_id
        and qualifier.award_kind in ('B4C', 'B6C')
    ))
    or
    (ss.final_award_mode = 'bis_ris' and fa.award_kind in ('BIS', 'RIS') and not exists (
      select 1 from bob_awards bob
      where bob.section_id = fa.section_id
        and bob.species_key = fa.species_key
        and bob.entry_id = fa.entry_id
    ))
),
invalid_final_awards as (
  select
    count(*)::integer as total,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'section_id', section_id,
          'species_key', species_key,
          'section_label', section_label,
          'award_code', award_code,
          'award_label', award_label,
          'reason', reason
        )
        order by section_sort_order, section_label, species_key, award_code
      ),
      '[]'::jsonb
    ) as items
  from invalid_final_award_rows
),
final_award_requirements as (
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'B4C'::text as award_kind, 'Best 4-Class'::text as award_label, 1 as award_order, true as required_for_readiness
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'four_six_bis' and exists (select 1 from breed_classified_bobs b where b.section_id = s.section_id and b.class_system = 'four')
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'B6C', 'Best 6-Class', 2, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'four_six_bis' and exists (select 1 from breed_classified_bobs b where b.section_id = s.section_id and b.class_system = 'six')
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'BIS', 'Best in Show', 3, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'four_six_bis' and exists (select 1 from breed_classified_bobs b where b.section_id = s.section_id)
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'BIS', 'Best in Show', 1, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'bis_ris' and exists (
    select 1 from bob_awards b
    where b.section_id = s.section_id and b.species_key = s.species_key
  )
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, 'RIS', 'Reserve in Show', 2, true
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'bis_ris' and (
    select count(*) from bob_awards b
    where b.section_id = s.section_id and b.species_key = s.species_key
  ) > 1
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order, v.award_kind, v.award_label, v.award_order, v.required_for_readiness
  from applicable_final_award_sections s cross join show_settings ss
  cross join (values ('BIS'::text, 'Best in Show'::text, 1, true), ('1RIS', 'First Reserve in Show', 2, true), ('2RIS', 'Second Reserve in Show', 3, false)) v(award_kind, award_label, award_order, required_for_readiness)
  where ss.final_award_mode in ('bis_1ris_2ris', 'bis_1ris_2ris_bbos')
  union all
  select s.section_id, s.species_key, s.section_label, s.sort_order,
    'BBOS', 'Best of the Best Opposite', 4, false
  from applicable_final_award_sections s cross join show_settings ss
  where ss.final_award_mode = 'bis_1ris_2ris_bbos'
),
final_award_counts as (
  select r.section_id, r.species_key, r.section_label, r.sort_order, r.award_kind, r.award_label, r.award_order, r.required_for_readiness,
    count(distinct fa.entry_id)::int as winner_count
  from final_award_requirements r
  left join final_awards fa on fa.section_id = r.section_id and fa.species_key = r.species_key and fa.award_kind = r.award_kind
  group by r.section_id, r.species_key, r.section_label, r.sort_order, r.award_kind, r.award_label, r.award_order, r.required_for_readiness
),
missing_final_awards as (
  select count(*) filter (where winner_count < 1 and required_for_readiness)::int as total from final_award_counts
),
missing_final_award_details as (
  select coalesce(jsonb_agg(jsonb_build_object('section_id', section_id, 'section_label', section_label, 'species', species_key, 'award_code', award_kind, 'award_label', award_label) order by sort_order, section_label, species_key, award_order) filter (where winner_count < 1 and required_for_readiness), '[]'::jsonb) as items from final_award_counts
),
suggested_final_awards as (
  select count(*) filter (where winner_count < 1 and not required_for_readiness)::int as total,
    coalesce(jsonb_agg(jsonb_build_object('section_id', section_id, 'section_label', section_label, 'species', species_key, 'award_code', award_kind, 'award_label', award_label) order by sort_order, section_label, species_key, award_order) filter (where winner_count < 1 and not required_for_readiness), '[]'::jsonb) as items from final_award_counts
),
duplicate_final_award_winners as (
  select coalesce(sum(greatest(winner_count - 1, 0)), 0)::int as total from final_award_counts
),
same_entry_final_award_conflicts as (
  select count(*)::int as total from (
    select fa.section_id, fa.species_key, fa.entry_id from final_awards fa cross join show_settings ss
    where ss.final_award_mode = 'four_six_bis' and fa.award_kind in ('B4C', 'B6C')
    group by fa.section_id, fa.species_key, fa.entry_id having count(distinct fa.award_kind) > 1
    union all
    select fa.section_id, fa.species_key, fa.entry_id from final_awards fa cross join show_settings ss
    where ss.final_award_mode <> 'four_six_bis' and fa.award_kind in ('BIS', 'RIS', '1RIS', '2RIS')
    group by fa.section_id, fa.species_key, fa.entry_id having count(distinct fa.award_kind) > 1
  ) conflicts
),
counts as (
  select (select total from missing_placement) as missing_placement_count,
    (select total from missing_judge) as missing_judge_count,
    (select total from duplicate_placement_groups) as duplicate_placement_group_count,
    (select total from missing_final_awards) as missing_final_award_count,
    ((select total from duplicate_final_award_winners) + (select total from same_entry_final_award_conflicts))::int as duplicate_final_award_count,
    (select total from invalid_final_awards) as invalid_final_award_count,
    (select items from missing_final_award_details) as missing_final_awards,
    (select items from invalid_final_awards) as invalid_final_awards,
    (select total from suggested_final_awards) as suggested_final_award_count,
    (select items from suggested_final_awards) as suggested_final_awards
)
select jsonb_build_object(
  'ready', missing_placement_count = 0 and missing_judge_count = 0 and duplicate_placement_group_count = 0 and missing_final_award_count = 0 and duplicate_final_award_count = 0 and invalid_final_award_count = 0,
  'missing_placement_count', missing_placement_count, 'missing_judge_count', missing_judge_count,
  'duplicate_placement_group_count', duplicate_placement_group_count, 'missing_final_award_count', missing_final_award_count,
  'duplicate_final_award_count', duplicate_final_award_count, 'invalid_final_award_count', invalid_final_award_count,
  'missing_final_awards', missing_final_awards, 'invalid_final_awards', invalid_final_awards,
  'suggested_final_award_count', suggested_final_award_count, 'suggested_final_awards', suggested_final_awards
) from counts;
$function$;

revoke all on function public.show_results_readiness_scoped(uuid, uuid[]) from public, anon;
grant execute on function public.show_results_readiness_scoped(uuid, uuid[]) to authenticated, service_role;


comment on function public.show_results_readiness_scoped(uuid, uuid[]) is
  'Checks scoped result and final-award readiness for four/six/BIS, BIS/RIS, BIS/1RIS/2RIS, and optional BBOS modes; placement 0 is excluded from duplicate-rank detection.';
