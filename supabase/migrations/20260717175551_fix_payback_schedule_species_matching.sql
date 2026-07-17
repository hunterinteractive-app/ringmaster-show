-- Match class-payback schedules to the entry species. Rabbit and cavy rows
-- may share the same shown-count range and placement; without this predicate,
-- each entry receives both rows and every class payback is duplicated.
-- The isolated baseline omits the production payback schedule tables and
-- retains a SETOF jsonb compatibility stub. Keep that stub in the fixture;
-- production has the schedule tables and receives the corrected definition.
do $block$
begin
  if to_regclass('public.show_payback_schedules') is null then
    raise notice 'Skipping production payback RPC in compatibility baseline';
    return;
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'report_payback_rows'
      and p.proargtypes = '2950 2950'::pg_catalog.oidvector
      and p.prorettype = 'jsonb'::pg_catalog.regtype
  ) then
    drop function public.report_payback_rows(uuid, uuid);
  end if;

  execute $payback_definition$
CREATE OR REPLACE FUNCTION "public"."report_payback_rows"("p_show_id" "uuid", "p_section_id" "uuid" DEFAULT NULL::"uuid") RETURNS TABLE("exhibitor_id" "uuid", "exhibitor_number" "text", "exhibitor_name" "text", "address_line1" "text", "address_line2" "text", "city" "text", "state" "text", "zip" "text", "section_id" "uuid", "section_label" "text", "section_kind" "text", "show_letter" "text", "source_type" "text", "award_code" "text", "award_label" "text", "entry_id" "uuid", "animal_id" "uuid", "breed_name" "text", "variety_name" "text", "group_name" "text", "class_name" "text", "sex" "text", "tattoo" "text", "placement" integer, "placement_label" "text", "eligible_count" integer, "amount_cents" integer, "payback_note" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$

WITH requested_sections AS (
  SELECT
    upper(s.kind::text) AS scope,
    upper(s.letter::text) AS show_letter
  FROM public.show_sections s
  WHERE s.show_id = p_show_id
    AND s.is_enabled = true
    AND (p_section_id IS NULL OR s.id = p_section_id)
),

scoped_entries AS (
  SELECT
    e.id AS entry_id,
    e.animal_id,
    e.show_id,
    e.section_id,
    e.exhibitor_id,
    e.tattoo,
    e.breed,
    e.variety,
    NULL::text AS group_name,
    e.class_name,
    e.sex,

    CASE
      WHEN lower(trim(coalesce(e.species::text, ''))) IN (
        'cavy',
        'cavies',
        'guinea pig',
        'guinea pigs'
      )
        THEN 'cavy'
      ELSE 'rabbit'
    END AS species_key,

    regexp_replace(
      lower(trim(coalesce(e.class_name, ''))),
      '[^a-z0-9]+',
      ' ',
      'g'
    ) AS class_key,

    CASE
      WHEN e.placement::text ~ '^[0-9]+$'
        THEN e.placement::integer
      ELSE NULL
    END AS placement,

    e.result_status,
    e.scratched_at,
    e.is_shown,
    e.is_disqualified,
    e.disqualified_reason

  FROM public.entries e

  WHERE e.show_id = p_show_id
    AND (
      p_section_id IS NULL
      OR e.section_id = p_section_id
    )
    AND e.scratched_at IS NULL
    AND coalesce(e.is_disqualified, false) = false
    AND coalesce(e.is_shown, true) = true
    AND lower(trim(coalesce(e.result_status, ''))) NOT IN (
      'no show',
      'noshow',
      'disqualified',
      'dq',
      'unworthy of award',
      'unworthy'
    )
),

class_counts AS (
  SELECT
    se.section_id,
    lower(trim(coalesce(se.breed, ''))) AS breed_key,
    lower(trim(coalesce(se.variety, ''))) AS variety_key,
    lower(trim(coalesce(se.class_name, ''))) AS class_key,
    lower(trim(coalesce(se.sex, ''))) AS sex_key,
    count(*)::integer AS eligible_count

  FROM scoped_entries se

  GROUP BY
    se.section_id,
    lower(trim(coalesce(se.breed, ''))),
    lower(trim(coalesce(se.variety, ''))),
    lower(trim(coalesce(se.class_name, ''))),
    lower(trim(coalesce(se.sex, '')))
),

class_paybacks AS (
  SELECT
    se.exhibitor_id,
    se.section_id,
    'class_placement'::text AS source_type,
    NULL::text AS award_code,

    concat(
      se.placement,
      public.ordinal_suffix(se.placement),
      ' Place'
    )::text AS award_label,

    se.entry_id,
    se.animal_id,
    se.breed AS breed_name,
    se.variety AS variety_name,
    se.group_name,
    se.class_name,
    se.sex,
    se.tattoo,
    se.placement,

    concat(
      se.placement,
      public.ordinal_suffix(se.placement)
    )::text AS placement_label,

    cc.eligible_count,
    r.amount_cents,

    concat(
      'Class payback: ',
      cc.eligible_count,
      ' shown, ',
      se.placement,
      public.ordinal_suffix(se.placement),
      ' place'
    )::text AS payback_note

  FROM scoped_entries se

  JOIN class_counts cc
    ON cc.section_id = se.section_id
   AND cc.breed_key = lower(trim(coalesce(se.breed, '')))
   AND cc.variety_key = lower(trim(coalesce(se.variety, '')))
   AND cc.class_key = lower(trim(coalesce(se.class_name, '')))
   AND cc.sex_key = lower(trim(coalesce(se.sex, '')))

  JOIN public.show_payback_schedules s
    ON s.show_id = p_show_id
   AND s.applies_to = 'class_placements'
   AND coalesce(s.is_enabled, true) = true
   AND (
     s.section_id = se.section_id
     OR (
       s.section_id IS NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.show_payback_schedules section_schedule
         WHERE section_schedule.show_id = p_show_id
           AND section_schedule.section_id = se.section_id
           AND section_schedule.applies_to = 'class_placements'
           AND coalesce(section_schedule.is_enabled, true) = true
       )
     )
   )

  JOIN public.show_payback_schedule_rows r
    ON r.schedule_id = s.id
   AND r.placement = se.placement
   AND (
     r.applies_to_species IS NULL
     OR lower(trim(r.applies_to_species)) IN ('', 'both', 'all')
     OR lower(trim(r.applies_to_species)) = se.species_key
   )
   AND cc.eligible_count >= r.min_shown
   AND (
     r.max_shown IS NULL
     OR cc.eligible_count <= r.max_shown
   )

  WHERE se.placement IS NOT NULL
    AND r.amount_cents > 0
),

award_special_paybacks AS (
  SELECT
    se.exhibitor_id,
    se.section_id,
    'special_money'::text AS source_type,
    ea.award_code::text,
    smr.award_label::text,
    se.entry_id,
    se.animal_id,
    se.breed AS breed_name,
    se.variety AS variety_name,
    se.group_name,
    se.class_name,
    se.sex,
    se.tattoo,
    NULL::integer AS placement,
    NULL::text AS placement_label,
    NULL::integer AS eligible_count,
    smr.amount_cents,

    concat(
      'Special money: ',
      smr.award_label
    )::text AS payback_note

  FROM public.entry_awards ea

  JOIN scoped_entries se
    ON se.entry_id = ea.entry_id

  JOIN public.show_special_money_rules smr
    ON smr.show_id = p_show_id
   AND upper(trim(smr.award_code)) =
       upper(trim(ea.award_code::text))
   AND upper(trim(smr.award_code)) NOT IN ('BD', 'BDPB')
   AND coalesce(smr.is_enabled, true) = true
   AND smr.amount_cents > 0

   AND (
     smr.applies_to_species IS NULL
     OR lower(trim(smr.applies_to_species)) IN ('', 'both', 'all')
     OR lower(trim(smr.applies_to_species)) = se.species_key
   )

   AND (
     smr.section_id = se.section_id
     OR (
       smr.section_id IS NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.show_special_money_rules section_rule
         WHERE section_rule.show_id = p_show_id
           AND section_rule.section_id = se.section_id
           AND upper(trim(section_rule.award_code)) =
               upper(trim(ea.award_code::text))
           AND coalesce(section_rule.is_enabled, true) = true
           AND (
             section_rule.applies_to_species IS NULL
             OR lower(trim(section_rule.applies_to_species))
                  IN ('', 'both', 'all')
             OR lower(trim(section_rule.applies_to_species)) =
                se.species_key
           )
       )
     )
   )

   AND (
     smr.breed_name IS NULL
     OR lower(trim(smr.breed_name)) =
        lower(trim(coalesce(se.breed, '')))
   )

   AND (
     smr.variety_name IS NULL
     OR lower(trim(smr.variety_name)) =
        lower(trim(coalesce(se.variety, '')))
   )
),

commercial_entries AS (
  SELECT
    se.*,

    CASE
      WHEN se.class_key IN ('meat pen', 'meat pens')
        THEN 'MEAT_PEN'

      WHEN se.class_key IN (
        'single fryer',
        'single fryers',
        'fryer',
        'fryers'
      )
        THEN 'SINGLE_FRYER'

      WHEN se.class_key IN ('roaster', 'roasters')
        THEN 'ROASTER'

      WHEN se.class_key IN ('stewer', 'stewers')
        THEN 'STEWER'

      ELSE NULL
    END AS commercial_class_code

  FROM scoped_entries se

  WHERE se.species_key = 'rabbit'
    AND se.placement IS NOT NULL
),

commercial_paybacks AS (
  SELECT
    ce.exhibitor_id,
    ce.section_id,
    'commercial_class'::text AS source_type,
    smr.award_code::text,
    smr.award_label::text,
    ce.entry_id,
    ce.animal_id,
    ce.breed AS breed_name,
    ce.variety AS variety_name,
    ce.group_name,
    ce.class_name,
    ce.sex,
    ce.tattoo,
    ce.placement,

    concat(
      ce.placement,
      public.ordinal_suffix(ce.placement)
    )::text AS placement_label,

    NULL::integer AS eligible_count,
    smr.amount_cents,

    concat(
      'Commercial class money: ',
      smr.award_label
    )::text AS payback_note

  FROM commercial_entries ce

  JOIN public.show_special_money_rules smr
    ON smr.show_id = p_show_id
   AND upper(trim(smr.award_code)) =
       concat(
         'COMMERCIAL_',
         ce.commercial_class_code,
         '_',
         ce.placement
       )
   AND coalesce(smr.is_enabled, true) = true
   AND smr.amount_cents > 0

   AND (
     smr.applies_to_species IS NULL
     OR lower(trim(smr.applies_to_species)) IN ('', 'both', 'all')
     OR lower(trim(smr.applies_to_species)) = 'rabbit'
   )

   AND (
     smr.section_id = ce.section_id
     OR (
       smr.section_id IS NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.show_special_money_rules section_rule
         WHERE section_rule.show_id = p_show_id
           AND section_rule.section_id = ce.section_id
           AND upper(trim(section_rule.award_code)) =
               concat(
                 'COMMERCIAL_',
                 ce.commercial_class_code,
                 '_',
                 ce.placement
               )
           AND coalesce(section_rule.is_enabled, true) = true
       )
     )
   )

  WHERE ce.commercial_class_code IS NOT NULL
),

overall_best_display_winners AS (
  SELECT
    standings.section_id,
    lower(trim(standings.species)) AS species_key,
    standings.exhibitor_id,
    standings.qualifying_entry_count,
    standings.display_points

  FROM requested_sections requested
  CROSS JOIN LATERAL public.report_best_display_standings(
    p_show_id := p_show_id,
    p_scope := requested.scope,
    p_show_letter := requested.show_letter,
    p_minimum_entries := 6
  ) standings

  WHERE standings.is_winner = true
    AND (
      p_section_id IS NULL
      OR standings.section_id = p_section_id
    )
),

overall_best_display_paybacks AS (
  SELECT
    winner.exhibitor_id,
    winner.section_id,
    'best_display'::text AS source_type,
    'BD'::text AS award_code,
    smr.award_label::text,
    representative.entry_id,
    representative.animal_id,
    representative.breed AS breed_name,
    representative.variety AS variety_name,
    representative.group_name,
    representative.class_name,
    representative.sex,
    representative.tattoo,
    NULL::integer AS placement,
    NULL::text AS placement_label,
    winner.qualifying_entry_count::integer AS eligible_count,
    smr.amount_cents,

    concat(
      'Best Display: ',
      smr.award_label,
      ' — ',
      winner.display_points,
      ' points'
    )::text AS payback_note

  FROM overall_best_display_winners winner

  JOIN public.show_special_money_rules smr
    ON smr.show_id = p_show_id
   AND upper(trim(smr.award_code)) = 'BD'
   AND coalesce(smr.is_enabled, true) = true
   AND smr.amount_cents > 0

   AND (
     smr.applies_to_species IS NULL
     OR lower(trim(smr.applies_to_species)) IN ('', 'both', 'all')
     OR lower(trim(smr.applies_to_species)) = winner.species_key
   )

   AND (
     smr.section_id = winner.section_id
     OR (
       smr.section_id IS NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.show_special_money_rules section_rule
         WHERE section_rule.show_id = p_show_id
           AND section_rule.section_id = winner.section_id
           AND upper(trim(section_rule.award_code)) = 'BD'
           AND coalesce(section_rule.is_enabled, true) = true
           AND (
             section_rule.applies_to_species IS NULL
             OR lower(trim(section_rule.applies_to_species))
                  IN ('', 'both', 'all')
             OR lower(trim(section_rule.applies_to_species)) =
                winner.species_key
           )
       )
     )
   )

  CROSS JOIN LATERAL (
    SELECT se.*
    FROM scoped_entries se
    WHERE se.section_id = winner.section_id
      AND se.exhibitor_id = winner.exhibitor_id
      AND se.species_key = winner.species_key
    ORDER BY
      se.placement NULLS LAST,
      se.entry_id
    LIMIT 1
  ) representative
),

best_display_breed_entry_rows AS (
  SELECT
    bd.section_id,
    upper(trim(coalesce(bd.scope, ''))) AS scope,
    upper(trim(coalesce(bd.show_letter, ''))) AS show_letter,
    lower(trim(coalesce(bd.species, ''))) AS species_key,
    trim(coalesce(bd.breed_name, '')) AS breed_name,
    bd.exhibitor_id,
    trim(coalesce(bd.exhibitor_name, 'Unknown Exhibitor')) AS exhibitor_name,
    coalesce(bd.is_point_earning, false) AS is_point_earning,
    coalesce(bd.display_points, 0)::numeric AS display_points

  FROM requested_sections requested
  CROSS JOIN LATERAL public.report_best_display_entry_rows(
    p_show_id := p_show_id,
    p_scope := requested.scope,
    p_show_letter := requested.show_letter
  ) bd

  WHERE (
      p_section_id IS NULL
      OR bd.section_id = p_section_id
    )
    AND nullif(trim(coalesce(bd.breed_name, '')), '') IS NOT NULL
),

best_display_breed_totals AS (
  SELECT
    rows.section_id,
    rows.scope,
    rows.show_letter,
    rows.species_key,
    rows.breed_name,
    rows.exhibitor_id,
    max(rows.exhibitor_name)::text AS exhibitor_name,
    count(*)::integer AS qualifying_entry_count,
    count(*) FILTER (
      WHERE rows.is_point_earning = true
    )::integer AS point_earning_entry_count,
    sum(rows.display_points)::numeric AS display_points

  FROM best_display_breed_entry_rows rows

  GROUP BY
    rows.section_id,
    rows.scope,
    rows.show_letter,
    rows.species_key,
    rows.breed_name,
    rows.exhibitor_id
),

eligible_best_display_breed_totals AS (
  SELECT *
  FROM best_display_breed_totals
  WHERE qualifying_entry_count >= 6
),

ranked_best_display_breed_totals AS (
  SELECT
    totals.*,

    dense_rank() OVER (
      PARTITION BY
        totals.section_id,
        totals.species_key,
        lower(trim(totals.breed_name))
      ORDER BY totals.display_points DESC
    )::integer AS display_rank,

    count(*) OVER (
      PARTITION BY
        totals.section_id,
        totals.species_key,
        lower(trim(totals.breed_name)),
        totals.display_points
    )::integer AS tied_at_points

  FROM eligible_best_display_breed_totals totals
),

best_display_breed_winners AS (
  SELECT *
  FROM ranked_best_display_breed_totals
  WHERE display_rank = 1
    AND tied_at_points = 1
),

best_display_breed_paybacks AS (
  SELECT
    winner.exhibitor_id,
    winner.section_id,
    'best_display_per_breed'::text AS source_type,
    'BDPB'::text AS award_code,
    smr.award_label::text,
    representative.entry_id,
    representative.animal_id,
    winner.breed_name::text AS breed_name,
    representative.variety AS variety_name,
    representative.group_name,
    representative.class_name,
    representative.sex,
    representative.tattoo,
    NULL::integer AS placement,
    NULL::text AS placement_label,
    winner.qualifying_entry_count::integer AS eligible_count,
    smr.amount_cents,

    concat(
      'Best Display Per Breed: ',
      winner.breed_name,
      ' — ',
      winner.display_points,
      ' points from ',
      winner.qualifying_entry_count,
      ' eligible entries'
    )::text AS payback_note

  FROM best_display_breed_winners winner

  JOIN public.show_special_money_rules smr
    ON smr.show_id = p_show_id
   AND upper(trim(smr.award_code)) = 'BDPB'
   AND coalesce(smr.is_enabled, true) = true
   AND smr.amount_cents > 0

   AND (
     smr.applies_to_species IS NULL
     OR lower(trim(smr.applies_to_species)) IN ('', 'both', 'all')
     OR lower(trim(smr.applies_to_species)) = winner.species_key
   )

   AND (
     smr.breed_name IS NULL
     OR lower(trim(smr.breed_name)) =
        lower(trim(winner.breed_name))
   )

   AND (
     smr.section_id = winner.section_id
     OR (
       smr.section_id IS NULL
       AND NOT EXISTS (
         SELECT 1
         FROM public.show_special_money_rules section_rule
         WHERE section_rule.show_id = p_show_id
           AND section_rule.section_id = winner.section_id
           AND upper(trim(section_rule.award_code)) = 'BDPB'
           AND coalesce(section_rule.is_enabled, true) = true
           AND (
             section_rule.applies_to_species IS NULL
             OR lower(trim(section_rule.applies_to_species))
                  IN ('', 'both', 'all')
             OR lower(trim(section_rule.applies_to_species)) =
                winner.species_key
           )
       )
     )
   )

  CROSS JOIN LATERAL (
    SELECT se.*
    FROM scoped_entries se
    WHERE se.section_id = winner.section_id
      AND se.exhibitor_id = winner.exhibitor_id
      AND se.species_key = winner.species_key
      AND lower(trim(coalesce(se.breed, ''))) =
          lower(trim(winner.breed_name))
    ORDER BY
      se.placement NULLS LAST,
      se.entry_id
    LIMIT 1
  ) representative
),

combined AS (
  SELECT * FROM class_paybacks

  UNION ALL

  SELECT * FROM award_special_paybacks

  UNION ALL

  SELECT * FROM commercial_paybacks

  UNION ALL

  SELECT * FROM overall_best_display_paybacks

  UNION ALL

  SELECT * FROM best_display_breed_paybacks
)

SELECT
  ex.id AS exhibitor_id,
  coalesce(ex.exhibitor_number::text, '') AS exhibitor_number,

  coalesce(
    nullif(trim(ex.showing_name), ''),
    nullif(
      trim(
        concat(
          coalesce(ex.first_name, ''),
          ' ',
          coalesce(ex.last_name, '')
        )
      ),
      ''
    ),
    'Unknown Exhibitor'
  ) AS exhibitor_name,

  coalesce(ex.address_line1, '')::text AS address_line1,
  coalesce(ex.address_line2, '')::text AS address_line2,
  coalesce(ex.city, '')::text AS city,
  coalesce(ex.state, '')::text AS state,
  coalesce(ex.zip, '')::text AS zip,

  ss.id AS section_id,

  concat(
    CASE
      WHEN lower(coalesce(ss.kind::text, '')) = 'youth'
        THEN 'Youth'
      ELSE 'Open'
    END,
    CASE
      WHEN coalesce(ss.letter, '') = ''
        THEN ''
      ELSE concat(' ', ss.letter)
    END
  ) AS section_label,

  ss.kind::text AS section_kind,
  ss.letter AS show_letter,

  c.source_type,
  c.award_code,
  c.award_label,

  c.entry_id,
  c.animal_id,
  c.breed_name,
  c.variety_name,
  c.group_name,
  c.class_name,
  c.sex,
  c.tattoo,

  c.placement,
  c.placement_label,
  c.eligible_count,
  c.amount_cents,
  c.payback_note

FROM combined c

LEFT JOIN public.exhibitors ex
  ON ex.id = c.exhibitor_id

LEFT JOIN public.show_sections ss
  ON ss.id = c.section_id

ORDER BY
  exhibitor_name,
  exhibitor_number,

  CASE
    WHEN lower(coalesce(ss.kind::text, '')) = 'youth'
      THEN 2
    ELSE 1
  END,

  ss.sort_order NULLS LAST,
  ss.letter,
  c.source_type,
  c.breed_name,
  c.variety_name,
  c.class_name,
  c.sex,
  c.tattoo,
  c.award_code;

$_$;
$payback_definition$;
end;
$block$;
