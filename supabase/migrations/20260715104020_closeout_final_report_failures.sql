-- Final read-only Closeout renderer fixes. This migration defines repair
-- commands but does not invoke them or modify application data.

-- The production payback RPC previously evaluated both best-display sources
-- for the entire show and filtered to p_section_id afterward. Push the exact
-- section scope into those expensive calls so indexed (show_id, section_id)
-- predicates are used throughout.
-- The isolated baseline omits the production payback schedule tables and
-- retains a SETOF jsonb compatibility stub. Keep that stub in the fixture;
-- production has the schedule tables and receives the optimized definition.
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


-- Balance validation must remain valid inside the worker's read-only
-- transaction. Read the persisted balance snapshot directly instead of
-- calling report_show_exhibitor_balances(), which rebuilds temp and persisted
-- balance state.
create or replace function public.report_show_exhibitor_balances_scoped(
  p_show_id uuid,
  p_section_ids uuid[]
)
returns setof jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_requested_ids uuid[];
  v_enabled_count integer;
  v_is_entire_show boolean;
  v_base jsonb;
  v_breakdown jsonb;
  v_scoped_breakdown jsonb;
  v_entry_count integer;
  v_fur_count integer;
  v_entries_cents integer;
  v_fur_cents integer;
  v_show_fee_cents integer;
  v_subtotal_cents integer;
  v_discount_cents integer;
  v_paid_online_cents integer;
  v_paid_manual_cents integer;
  v_refunded_cents integer;
  v_has_unallocated_discount boolean;
  v_has_unallocated_payment boolean;
  v_has_unallocated_adjustment boolean;
  v_allocation_status text;
  v_ambiguity_reasons jsonb;
begin
  if p_show_id is null then
    raise exception 'show_id is required' using errcode = '22023';
  end if;

  if p_section_ids is null or cardinality(p_section_ids) = 0 then
    raise exception 'section_ids must contain at least one section'
      using errcode = '22023';
  end if;

  if not exists (select 1 from public.shows s where s.id = p_show_id) then
    raise exception 'Show not found' using errcode = 'P0002';
  end if;

  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have access to this show'
      using errcode = '42501';
  end if;

  select array_agg(x.section_id order by x.section_id)
  into v_requested_ids
  from (select distinct unnest(p_section_ids) as section_id) x;

  if exists (
    select 1
    from unnest(v_requested_ids) requested(section_id)
    left join public.show_sections ss
      on ss.id = requested.section_id
     and ss.show_id = p_show_id
     and ss.is_enabled = true
    where ss.id is null
  ) then
    raise exception
      'Every section_id must identify an enabled section in the requested show'
      using errcode = '22023';
  end if;

  select count(*) into v_enabled_count
  from public.show_sections ss
  where ss.show_id = p_show_id and ss.is_enabled = true;

  v_is_entire_show := cardinality(v_requested_ids) = v_enabled_count;

  for v_base in
    select (
      to_jsonb(b)
        - 'id'
        - 'cart_id'
        - 'created_at'
        - 'updated_at'
        - 'calculated_at'
        - 'fee_snapshot'
        - 'entry_cart_id'
        - 'latest_show_payment_id'
        - 'latest_payment_intent_id'
        - 'latest_checkout_session_id'
    ) || jsonb_build_object(
      'balance_id', b.id,
      'exhibitor_user_id', coalesce(
        to_jsonb(ex) -> 'user_id',
        to_jsonb(ex) -> 'exhibitor_user_id'
      ),
      'exhibitor_name', coalesce(
        nullif(btrim(ex.display_name), ''),
        nullif(btrim(ex.showing_name), ''),
        nullif(btrim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
        'Exhibitor'
      ),
      'showing_name', ex.showing_name,
      'display_name', ex.display_name,
      'first_name', ex.first_name,
      'last_name', ex.last_name,
      'exhibitor_type', ex.type,
      'phone', ex.phone,
      'email', ex.email,
      'address_line1', ex.address_line1,
      'address_line2', ex.address_line2,
      'city', ex.city,
      'state', ex.state,
      'zip', ex.zip,
      'arba_number', ex.arba_number
    )
    from public.show_exhibitor_balances b
    left join public.exhibitors ex on ex.id = b.exhibitor_id
    where b.show_id = p_show_id
    order by b.id
  loop
    v_breakdown := case
      when jsonb_typeof(v_base -> 'section_breakdown') = 'array'
        then v_base -> 'section_breakdown'
      else '[]'::jsonb
    end;

    if v_is_entire_show then
      return next v_base || jsonb_build_object(
        'scope_is_entire_show', true,
        'payment_allocation_status', 'exact_entire_show',
        'payment_allocation_ambiguity_reasons', '[]'::jsonb
      );
      continue;
    end if;

    select
      coalesce(jsonb_agg(item order by item ->> 'section_id'), '[]'::jsonb),
      coalesce(sum((item ->> 'entry_count')::integer), 0)::integer,
      coalesce(sum((item ->> 'fur_count')::integer), 0)::integer,
      coalesce(sum((item ->> 'entries_subtotal_cents')::integer), 0)::integer,
      coalesce(sum((item ->> 'fur_subtotal_cents')::integer), 0)::integer,
      coalesce(sum((item ->> 'show_fee_cents')::integer), 0)::integer
    into
      v_scoped_breakdown,
      v_entry_count,
      v_fur_count,
      v_entries_cents,
      v_fur_cents,
      v_show_fee_cents
    from jsonb_array_elements(v_breakdown) item
    where (item ->> 'section_id')::uuid = any(v_requested_ids);

    if v_scoped_breakdown = '[]'::jsonb then
      continue;
    end if;

    v_subtotal_cents := v_entries_cents + v_fur_cents + v_show_fee_cents;
    v_discount_cents := coalesce((v_base ->> 'discount_cents')::integer, 0);
    v_paid_online_cents := coalesce((v_base ->> 'paid_online_cents')::integer, 0);
    v_paid_manual_cents := coalesce((v_base ->> 'paid_manual_cents')::integer, 0);
    v_refunded_cents := coalesce((v_base ->> 'refunded_cents')::integer, 0);

    -- Current snapshots record these values only at balance/cart granularity.
    -- They therefore cannot be attributed to one selected section safely.
    v_has_unallocated_discount := v_discount_cents <> 0;
    v_has_unallocated_payment :=
      v_paid_online_cents <> 0 or v_paid_manual_cents <> 0
      or v_refunded_cents <> 0;
    v_has_unallocated_adjustment :=
      coalesce((v_base ->> 'subtotal_before_discount_cents')::integer, 0)
      <> coalesce((
        select sum(
          coalesce((item ->> 'entries_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'fur_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'show_fee_cents')::integer, 0)
        )::integer
        from jsonb_array_elements(v_breakdown) item
      ), 0);

    v_allocation_status := case
      when v_has_unallocated_discount
        or v_has_unallocated_payment
        or v_has_unallocated_adjustment
      then 'ambiguous'
      else 'exact'
    end;
    v_ambiguity_reasons := jsonb_strip_nulls(jsonb_build_object(
      'discount', case when v_has_unallocated_discount then
        'The stored discount applies to the whole exhibitor balance and has no section allocation.' end,
      'payment', case when v_has_unallocated_payment then
        'Financial payments for this exhibitor are recorded only at the whole-show level and cannot be allocated reliably to the selected sections.' end,
      'adjustment', case when v_has_unallocated_adjustment then
        'The stored balance contains charges or adjustments that are not represented in its section breakdown.' end
    ));

    select coalesce(jsonb_agg(
      item || jsonb_build_object(
        'discount_cents', 0,
        'paid_online_cents', 0,
        'paid_manual_cents', 0,
        'refunded_cents', 0,
        'balance_due_cents',
          coalesce((item ->> 'entries_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'fur_subtotal_cents')::integer, 0)
          + coalesce((item ->> 'show_fee_cents')::integer, 0)
      ) order by item ->> 'section_id'
    ), '[]'::jsonb)
    into v_scoped_breakdown
    from jsonb_array_elements(v_scoped_breakdown) item;

    return next v_base || jsonb_build_object(
      'scope_is_entire_show', false,
      'section_breakdown', v_scoped_breakdown,
      'entry_count', v_entry_count,
      'fur_count', v_fur_count,
      'entries_subtotal_cents', v_entries_cents,
      'fur_subtotal_cents', v_fur_cents,
      'show_fee_subtotal_cents', v_show_fee_cents,
      'subtotal_before_discount_cents', v_subtotal_cents,
      'discount_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'calculated_total_cents', case when v_allocation_status = 'exact' then v_subtotal_cents else null end,
      'paid_online_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'paid_manual_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'refunded_cents', case when v_allocation_status = 'exact' then 0 else null end,
      'balance_due_cents', case when v_allocation_status = 'exact' then v_subtotal_cents else null end,
      'payment_status', case when v_allocation_status = 'exact' then
        case when v_subtotal_cents <= 0 then 'paid' else 'unpaid' end
        else 'allocation_ambiguous' end,
      'payment_allocation_status', v_allocation_status,
      'payment_allocation_ambiguity_reasons', v_ambiguity_reasons
    );
  end loop;
end;
$$;

comment on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
is 'Read-only exact-section Closeout balances derived from persisted snapshots; performs no temporary-table or application-data mutations.';

revoke all on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
  from public, anon;
grant execute on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
  to authenticated, service_role;


-- Keep the review panel on the same exact scoped dashboard response. The
-- artifact's structural root cause takes precedence over later lease history;
-- task attempts and failure time still remain visible as history.
create or replace function public.get_closeout_dashboard_scoped(
  p_show_id uuid,
  p_scope_key text,
  p_section_ids uuid[],
  p_artifact_limit integer default 100,
  p_artifact_offset integer default 0,
  p_report_name public.report_type default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_dashboard jsonb;
  v_last_activity_at timestamptz;
  v_completed_at timestamptz;
  v_active_count integer := 0;
  v_review_reports jsonb := '[]'::jsonb;
begin
  v_dashboard := public.get_closeout_dashboard_scoped_without_activity(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );

  with selected_run as (
    select f.id
    from public.show_finalize_runs f
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  current_tasks as (
    select q.*
    from public.show_task_queue q
    join public.show_report_artifacts a
      on a.id = q.report_artifact_id and a.is_current = true
    join selected_run r on r.id = q.finalize_run_id
    where q.show_id = p_show_id
      and q.task_type = 'render_report'::public.show_task_type
  )
  select
    max(greatest(
      q.created_at,
      q.claimed_at,
      q.started_at,
      q.heartbeat_at,
      q.completed_at,
      q.failed_at
    )),
    max(coalesce(q.completed_at, q.failed_at)),
    count(*) filter (
      where q.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status
      )
    )::integer
  into v_last_activity_at, v_completed_at, v_active_count
  from current_tasks q;

  with selected_run as (
    select f.id
    from public.show_finalize_runs f
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  current_artifacts as (
    select a.*
    from public.show_report_artifacts a
    join selected_run r on r.id = a.finalize_run_id
    where a.show_id = p_show_id
      and a.is_current = true
  ),
  review_rows as (
    select
      a.*,
      q.task_status,
      q.error_category task_error_category,
      q.error_message task_error_message,
      q.last_error,
      q.attempt_count,
      q.max_attempts,
      coalesce(
        q.failed_at,
        q.completed_at,
        q.heartbeat_at,
        q.started_at,
        q.claimed_at,
        q.created_at
      ) last_attempted_at,
      (
        coalesce(
          q.task_status = 'failed'::public.show_task_status
            and q.attempt_count < q.max_attempts,
          false
        )
        or coalesce(repair.is_repairable, false)
        or (
          a.report_name in (
            'payback_report'::public.report_type,
            'unpaid_balances_report'::public.report_type
          )
          and (
            coalesce(q.last_error, '') ilike '%code: 57014%'
            or coalesce(q.last_error, '') ilike '%code: 25006%'
          )
        )
      ) retryable
    from current_artifacts a
    left join lateral (
      select task.*
      from public.show_task_queue task
      where task.report_artifact_id = a.id
        and task.task_type = 'render_report'::public.show_task_type
      order by coalesce(
        task.failed_at,
        task.completed_at,
        task.heartbeat_at,
        task.started_at,
        task.claimed_at,
        task.created_at
      ) desc nulls last,
      task.created_at desc,
      task.id desc
      limit 1
    ) q on true
    left join lateral public.resolve_closeout_artifact_scope(
      a.show_id,
      a.finalize_run_id,
      a.report_name,
      a.metadata
    ) repair on a.artifact_status = 'failed'::public.artifact_status
      and a.metadata ->> 'error_category' = 'invalid_scope'
    where a.artifact_status in (
        'queued'::public.artifact_status,
        'failed'::public.artifact_status
      )
      or q.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status,
        'failed'::public.show_task_status
      )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'artifact_id', a.id,
    'finalize_run_id', a.finalize_run_id,
    'report_name', a.report_name,
    'artifact_status', a.artifact_status,
    'task_status', coalesce(a.task_status::text, 'missing'),
    'review_group', case
      when a.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status
      ) then 'active'
      when a.artifact_status = 'failed'::public.artifact_status
        or a.task_status = 'failed'::public.show_task_status
        then case when a.retryable
          then 'retryable_failure'
          else 'non_retryable_failure'
        end
      else 'missing'
    end,
    'section_ids', to_jsonb(a.section_ids),
    'section_id', a.metadata ->> 'section_id',
    'section_label', a.metadata ->> 'section_label',
    'show_letter', a.metadata ->> 'show_letter',
    'scope', a.metadata ->> 'scope',
    'species', a.metadata ->> 'species',
    'exhibitor_name', a.metadata ->> 'exhibitor_name',
    'breed_name', a.metadata ->> 'breed_name',
    'club_name', a.metadata ->> 'club_name',
    'sanctioning_body', a.metadata ->> 'sanctioning_body',
    'error_category', case
      when a.metadata ->> 'error_category' = 'invalid_scope'
        then 'invalid_scope'
      when coalesce(a.last_error, '') ilike '%code: 57014%'
        then 'statement_timeout'
      when coalesce(a.last_error, '') ilike '%code: 25006%'
        then 'read_only_violation'
      else coalesce(
        a.metadata ->> 'error_category',
        a.task_error_category,
        'render_error'
      )
    end,
    'error_message', case
      when a.metadata ->> 'error_category' = 'invalid_scope'
        then coalesce(
          a.metadata ->> 'error_message',
          'The report artifact has incomplete structured scope metadata.'
        )
      when coalesce(a.last_error, '') ilike '%code: 57014%'
        then 'The Paybacks report query exceeded its database time limit.'
      when coalesce(a.last_error, '') ilike '%code: 25006%'
        then 'The balance report encountered an operation that is not allowed during read-only rendering.'
      else coalesce(
        a.metadata ->> 'error_message',
        a.task_error_message,
        'The report could not be rendered.'
      )
    end,
    'task_history_category', a.task_error_category,
    'task_history_message', a.task_error_message,
    'retryable', a.retryable,
    'attempt_count', coalesce(a.attempt_count, 0),
    'max_attempts', coalesce(a.max_attempts, 0),
    'last_attempted_at', a.last_attempted_at
  ) order by
    case
      when a.retryable then 1
      when a.artifact_status = 'failed'::public.artifact_status
        or a.task_status = 'failed'::public.show_task_status then 2
      when a.task_status is null then 3
      else 4
    end,
    a.report_name,
    a.created_at,
    a.id
  ), '[]'::jsonb)
  into v_review_reports
  from review_rows a;

  v_dashboard := jsonb_set(
    v_dashboard,
    '{task_counts}',
    coalesce(v_dashboard -> 'task_counts', '{}'::jsonb) ||
      jsonb_build_object(
        'last_activity_at', v_last_activity_at,
        'completed_at', case when v_active_count = 0 then v_completed_at end
      ),
    true
  );

  return jsonb_set(
    v_dashboard,
    '{review_reports}',
    v_review_reports,
    true
  );
end;
$function$;

-- Preview by default. Execution creates canonical replacement artifacts and
-- fresh tasks while leaving every old artifact/task row available as history.
create or replace function public.repair_final_closeout_report_failures(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_artifact public.show_report_artifacts%rowtype;
  v_scope record;
  v_metadata jsonb;
  v_scope_key text;
  v_artifact_key text;
  v_replacement_id uuid;
  v_repairable_exhibitors integer := 0;
  v_obsolete_exhibitors integer := 0;
  v_render_fixes integer := 0;
  v_queued integer := 0;
  v_obsolete_names jsonb := '[]'::jsonb;
begin
  if p_show_id is null or p_finalize_run_id is null then
    raise exception 'show_id and finalize_run_id are required'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.show_finalize_runs f
    where f.id = p_finalize_run_id
      and f.show_id = p_show_id
  ) then
    raise exception 'Finalize run does not belong to the requested show'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_show_id::text || ':' || p_finalize_run_id::text ||
      ':final-closeout-report-repair',
    0
  ));

  for v_artifact in
    select a.*
    from public.show_report_artifacts a
    where a.show_id = p_show_id
      and a.finalize_run_id = p_finalize_run_id
      and a.is_current = true
      and a.artifact_status = 'failed'::public.artifact_status
      and (
        (
          a.report_name = 'exhibitor_report'::public.report_type
          and a.metadata ->> 'error_category' in (
            'invalid_scope', 'missing_exhibitor_entries'
          )
        )
        or a.report_name in (
          'payback_report'::public.report_type,
          'unpaid_balances_report'::public.report_type
        )
      )
    order by a.created_at, a.id
    for update
  loop
    if v_artifact.report_name = 'exhibitor_report'::public.report_type then
      select * into v_scope
      from public.resolve_closeout_artifact_scope(
        v_artifact.show_id,
        v_artifact.finalize_run_id,
        v_artifact.report_name,
        v_artifact.metadata
      );

      if not coalesce(v_scope.is_repairable, false) then
        v_obsolete_exhibitors := v_obsolete_exhibitors + 1;
        v_obsolete_names := v_obsolete_names || jsonb_build_array(
          coalesce(
            nullif(btrim(v_artifact.metadata ->> 'exhibitor_name'), ''),
            v_artifact.metadata ->> 'exhibitor_id',
            v_artifact.id::text
          )
        );
        if not p_dry_run then
          update public.show_report_artifacts a
          set metadata = a.metadata || jsonb_build_object(
                'error_category', 'missing_exhibitor_entries',
                'error_message',
                  'This exhibitor has no qualifying shown entries in the selected Closeout scope.'
              ),
              error_count = greatest(a.error_count, 1),
              updated_at = now()
          where a.id = v_artifact.id;
        end if;
        continue;
      end if;

      v_repairable_exhibitors := v_repairable_exhibitors + 1;
      if p_dry_run then
        continue;
      end if;

      v_metadata := (
        v_scope.metadata - 'error_category' - 'error_message'
      ) || jsonb_build_object(
        'repair_of_artifact_id', v_artifact.id,
        'report_scope', 'repair:' || v_artifact.id::text
      );
    else
      v_render_fixes := v_render_fixes + 1;
      if p_dry_run then
        continue;
      end if;

      v_metadata := (
        v_artifact.metadata - 'error_category' - 'error_message'
      ) || jsonb_build_object(
        'repair_of_artifact_id', v_artifact.id,
        'report_scope', 'repair:' || v_artifact.id::text
      );
    end if;

    v_artifact_key := public.closeout_artifact_identity(
      v_artifact.report_name,
      v_metadata
    );
    v_scope_key := public.closeout_artifact_scope_key(
      v_artifact.show_id,
      v_artifact.report_name,
      case
        when v_artifact.report_name = 'exhibitor_report'::public.report_type
          then v_scope.section_ids
        else v_artifact.section_ids
      end,
      v_metadata
    );
    v_metadata := v_metadata || jsonb_build_object(
      'scope_key', v_scope_key,
      'section_ids', to_jsonb(case
        when v_artifact.report_name = 'exhibitor_report'::public.report_type
          then v_scope.section_ids
        else v_artifact.section_ids
      end)
    );

    select a.id into v_replacement_id
    from public.show_report_artifacts a
    where a.finalize_run_id = v_artifact.finalize_run_id
      and a.artifact_key = v_artifact_key
      and a.is_current = true
    limit 1;

    if v_replacement_id is null then
      update public.show_report_artifacts a
      set is_current = false,
          superseded_at = coalesce(a.superseded_at, now()),
          updated_at = now()
      where a.id = v_artifact.id;

      insert into public.show_report_artifacts (
        show_id,
        finalize_run_id,
        report_name,
        artifact_status,
        metadata,
        warning_count,
        error_count,
        is_current,
        generation,
        scope_key,
        section_ids,
        artifact_key
      ) values (
        v_artifact.show_id,
        v_artifact.finalize_run_id,
        v_artifact.report_name,
        'queued'::public.artifact_status,
        v_metadata,
        v_artifact.warning_count,
        0,
        true,
        v_artifact.generation + 1,
        v_scope_key,
        case
          when v_artifact.report_name = 'exhibitor_report'::public.report_type
            then v_scope.section_ids
          else v_artifact.section_ids
        end,
        v_artifact_key
      ) returning id into v_replacement_id;
    end if;
  end loop;

  if not p_dry_run then
    select public.enqueue_report_render_tasks(p_show_id, p_finalize_run_id)
    into v_queued;
  end if;

  return jsonb_build_object(
    'dry_run', p_dry_run,
    'show_id', p_show_id,
    'finalize_run_id', p_finalize_run_id,
    'repairable_exhibitor_reports', v_repairable_exhibitors,
    'obsolete_exhibitor_reports', v_obsolete_exhibitors,
    'obsolete_exhibitor_names', v_obsolete_names,
    'render_reports_to_requeue', v_render_fixes,
    'queued_tasks', v_queued
  );
end;
$function$;

revoke all on function public.repair_final_closeout_report_failures(
  uuid, uuid, boolean
) from public, anon, authenticated;
grant execute on function public.repair_final_closeout_report_failures(
  uuid, uuid, boolean
) to service_role;


-- An exhibitor report is valid only when the exhibitor has at least one shown,
-- non-scratched, non-disqualified, non-test entry in the finalize-run scope.
create or replace function public.resolve_closeout_artifact_scope(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_report_name public.report_type,
  p_metadata jsonb
)
returns table(
  is_repairable boolean,
  failure_reason text,
  scope_key text,
  section_ids uuid[],
  metadata jsonb,
  artifact_key text
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_run public.show_finalize_runs%rowtype;
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_section public.show_sections%rowtype;
  v_section_id uuid;
  v_exhibitor_id uuid;
  v_sections uuid[];
  v_species text;
  v_identity text;
begin
  select f.* into v_run
  from public.show_finalize_runs f
  where f.id = p_finalize_run_id and f.show_id = p_show_id;

  if v_run.id is null or cardinality(coalesce(v_run.section_ids, '{}'::uuid[])) = 0 then
    return query select false, 'missing_finalize_run_scope', null::text,
      '{}'::uuid[], v_metadata, null::text;
    return;
  end if;

  if p_report_name::text in (
    'arba_report', 'sweepstakes_report', 'breed_results_detail_report',
    'details_by_breed', 'exh_by_breed', 'best_display_report'
  ) then
    if coalesce(v_metadata ->> 'section_id', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return query select false, 'missing_section_id', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_section_id := (v_metadata ->> 'section_id')::uuid;
    select s.* into v_section
    from public.show_sections s
    where s.id = v_section_id and s.show_id = p_show_id
      and s.id = any(v_run.section_ids);
    if v_section.id is null then
      return query select false, 'section_not_in_finalize_scope', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    if nullif(btrim(v_metadata ->> 'scope'), '') is not null
       and upper(btrim(v_metadata ->> 'scope')) <> upper(v_section.kind::text) then
      return query select false, 'section_kind_mismatch', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    if nullif(btrim(v_metadata ->> 'show_letter'), '') is not null
       and upper(btrim(v_metadata ->> 'show_letter')) <> upper(v_section.letter) then
      return query select false, 'show_letter_mismatch', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_sections := array[v_section.id];
    v_metadata := v_metadata || jsonb_build_object(
      'section_id', v_section.id,
      'scope', upper(v_section.kind::text),
      'show_letter', upper(v_section.letter)
    );

    if p_report_name::text in (
      'sweepstakes_report', 'breed_results_detail_report',
      'details_by_breed', 'exh_by_breed', 'best_display_report'
    ) then
      if nullif(btrim(v_metadata ->> 'breed_name'), '') is null
         and p_report_name::text in ('sweepstakes_report', 'breed_results_detail_report') then
        return query select false, 'missing_breed_name', null::text,
          '{}'::uuid[], v_metadata, null::text;
        return;
      end if;
      v_species := lower(nullif(btrim(v_metadata ->> 'species'), ''));
      if v_species is null and nullif(btrim(v_metadata ->> 'breed_name'), '') is not null then
        select case when count(distinct lower(b.species::text)) = 1
                    then min(lower(b.species::text)) end
        into v_species
        from public.breeds b
        where lower(btrim(b.name)) = lower(btrim(v_metadata ->> 'breed_name'));
      end if;
      if v_species is null then
        select case when count(distinct lower(e.species::text)) = 1
                    then min(lower(e.species::text)) end
        into v_species
        from public.entries e
        where e.show_id = p_show_id and e.section_id = v_section.id
          and e.is_shown = true and e.scratched_at is null;
      end if;
      if v_species not in ('rabbit', 'cavy') then
        return query select false, 'ambiguous_species', null::text,
          '{}'::uuid[], v_metadata, null::text;
        return;
      end if;
      v_metadata := v_metadata || jsonb_build_object('species', v_species);
    end if;
  elsif p_report_name::text in ('exhibitor_report', 'checkin_sheet', 'legs') then
    if coalesce(v_metadata ->> 'exhibitor_id', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return query select false, 'missing_exhibitor_id', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_exhibitor_id := (v_metadata ->> 'exhibitor_id')::uuid;
    select array_agg(distinct e.section_id order by e.section_id)
    into v_sections
    from public.entries e
    where e.show_id = p_show_id and e.exhibitor_id = v_exhibitor_id
      and e.section_id = any(v_run.section_ids)
      and e.is_shown = true
      and e.scratched_at is null
      and coalesce(e.is_disqualified, false) = false
      and coalesce(e.is_test, false) = false
      and lower(coalesce(e.status, '')) not in (
        'deleted', 'cancelled', 'canceled', 'scratched'
      )
      and lower(btrim(coalesce(e.result_status, ''))) not in (
        'no show', 'no_show', 'noshow', 'disqualified', 'dq',
        'unworthy of award', 'unworthy'
      );
    if cardinality(coalesce(v_sections, '{}'::uuid[])) = 0 then
      return query select false, 'missing_exhibitor_entries', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
  elsif p_report_name::text in (
    'unpaid_balances_report', 'paid_exhibitor_report',
    'entered_exhibitors_contact_report', 'ribbon_payout_report',
    'payback_report', 'judge_report', 'breed_judged_totals_report'
  ) then
    v_sections := v_run.section_ids;
  else
    return query select false, 'unsupported_report_scope', null::text,
      '{}'::uuid[], v_metadata, null::text;
    return;
  end if;

  v_sections := array(
    select distinct section_id from unnest(v_sections) section_id order by section_id
  );
  v_metadata := v_metadata || jsonb_build_object(
    'run_scope_key', v_run.scope_key,
    'section_ids', to_jsonb(v_sections)
  );
  v_identity := public.closeout_artifact_identity(p_report_name, v_metadata);
  scope_key := public.closeout_artifact_scope_key(
    p_show_id, p_report_name, v_sections, v_metadata
  );
  metadata := v_metadata || jsonb_build_object('scope_key', scope_key);
  section_ids := v_sections;
  artifact_key := v_identity;
  is_repairable := true;
  failure_reason := null;
  return next;
end;
$function$;


revoke all on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;
