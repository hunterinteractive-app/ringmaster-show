-- ARBA artifacts record their species as an array (for example, ["rabbit"]),
-- while most report artifacts use a single string.  The scoped dashboard must
-- accept both shapes or it hides generated ARBA reports from the selector.

do $block$
declare
  v_definition text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_closeout_dashboard_scoped_for_species'
    and p.pronargs = 7;

  if v_definition is null then
    raise exception 'get_closeout_dashboard_scoped_for_species is required';
  end if;

  v_old := 'lower(coalesce(report.value -> ''metadata'' ->> ''species'', '''')) = v_species';
  v_new := '(lower(coalesce(report.value -> ''metadata'' ->> ''species'', '''')) = v_species or coalesce(report.value -> ''metadata'' -> ''species'', ''[]''::jsonb) ? v_species)';
  v_definition := replace(v_definition, v_old, v_new);

  v_old := 'lower(coalesce(' || chr(10) ||
    '    review.value ->> ''species'',' || chr(10) ||
    '    review.value -> ''metadata'' ->> ''species'',' || chr(10) ||
    '    ''''' || chr(10) ||
    '  )) = v_species';
  v_new := '(lower(coalesce(' || chr(10) ||
    '    review.value ->> ''species'',' || chr(10) ||
    '    review.value -> ''metadata'' ->> ''species'',' || chr(10) ||
    '    ''''' || chr(10) ||
    '  )) = v_species or coalesce(review.value -> ''metadata'' -> ''species'', ''[]''::jsonb) ? v_species)';
  v_definition := replace(v_definition, v_old, v_new);

  v_old := 'lower(species_artifact.metadata ->> ''species'') = v_species';
  v_new := '(lower(species_artifact.metadata ->> ''species'') = v_species or coalesce(species_artifact.metadata -> ''species'', ''[]''::jsonb) ? v_species)';
  v_definition := replace(v_definition, v_old, v_new);

  v_old := 'lower(a.metadata ->> ''species'') = v_species';
  v_new := '(lower(a.metadata ->> ''species'') = v_species or coalesce(a.metadata -> ''species'', ''[]''::jsonb) ? v_species)';
  v_definition := replace(v_definition, v_old, v_new);

  execute v_definition;
end;
$block$;

-- The active dashboard function also treats untagged artifacts as in-scope.
-- Its predicates have this more defensive shape, so extend those predicates
-- with an array-membership check as well.
do $block$
declare
  v_definition text;
  v_old text;
  v_new text;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_closeout_dashboard_scoped_for_species'
    and p.pronargs = 7;

  v_old := $match$(
    nullif(lower(btrim(coalesce(
      report.value -> 'metadata' ->> 'species',
      ''
    ))), '') is null
    or lower(btrim(report.value -> 'metadata' ->> 'species')) = v_species
  )$match$;
  v_new := $match$(
    nullif(lower(btrim(coalesce(
      report.value -> 'metadata' ->> 'species',
      ''
    ))), '') is null
    or lower(btrim(report.value -> 'metadata' ->> 'species')) = v_species
    or coalesce(report.value -> 'metadata' -> 'species', '[]'::jsonb) ? v_species
  )$match$;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := $match$(
    nullif(lower(btrim(coalesce(
      review.value ->> 'species',
      review.value -> 'metadata' ->> 'species',
      ''
    ))), '') is null
    or lower(btrim(coalesce(
      review.value ->> 'species',
      review.value -> 'metadata' ->> 'species'
    ))) = v_species
  )$match$;
  v_new := $match$(
    nullif(lower(btrim(coalesce(
      review.value ->> 'species',
      review.value -> 'metadata' ->> 'species',
      ''
    ))), '') is null
    or lower(btrim(coalesce(
      review.value ->> 'species',
      review.value -> 'metadata' ->> 'species'
    ))) = v_species
    or coalesce(review.value -> 'metadata' -> 'species', '[]'::jsonb) ? v_species
  )$match$;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := $match$(
            nullif(lower(btrim(coalesce(
              species_artifact.metadata ->> 'species',
              ''
            ))), '') is null
            or lower(btrim(species_artifact.metadata ->> 'species')) = v_species
          )$match$;
  v_new := $match$(
            nullif(lower(btrim(coalesce(
              species_artifact.metadata ->> 'species',
              ''
            ))), '') is null
            or lower(btrim(species_artifact.metadata ->> 'species')) = v_species
            or coalesce(species_artifact.metadata -> 'species', '[]'::jsonb) ? v_species
          )$match$;
  v_definition := replace(v_definition, v_old, v_new);

  v_old := $match$(
      nullif(lower(btrim(coalesce(a.metadata ->> 'species', ''))), '') is null
      or lower(btrim(a.metadata ->> 'species')) = v_species
    )$match$;
  v_new := $match$(
      nullif(lower(btrim(coalesce(a.metadata ->> 'species', ''))), '') is null
      or lower(btrim(a.metadata ->> 'species')) = v_species
      or coalesce(a.metadata -> 'species', '[]'::jsonb) ? v_species
    )$match$;
  v_definition := replace(v_definition, v_old, v_new);

  execute v_definition;
end;
$block$;
