-- Keep finalize-time exhibitor artifact selection identical to canonical
-- artifact-scope validation. Previously, a no-show, disqualified, test,
-- cancelled, or unworthy entry could create an exhibitor/check-in/legs
-- artifact that the scope trigger immediately rejected, rolling back the
-- entire finalize transaction with missing_exhibitor_entries.
do $block$
declare
  v_definition text;
  v_exhibitor_needle text :=
    '        and e.exhibitor_id = ex.id and e.is_shown = true' || chr(10) ||
    '        and e.scratched_at is null and lower(coalesce(e.status, '''')) <> ''scratched''';
  v_exhibitor_replacement text :=
    '        and e.exhibitor_id = ex.id and e.is_shown = true' || chr(10) ||
    '        and e.scratched_at is null' || chr(10) ||
    '        and coalesce(e.is_disqualified, false) = false' || chr(10) ||
    '        and coalesce(e.is_test, false) = false' || chr(10) ||
    '        and lower(coalesce(e.status, '''')) not in (' || chr(10) ||
    '          ''deleted'', ''cancelled'', ''canceled'', ''scratched''' || chr(10) ||
    '        )' || chr(10) ||
    '        and lower(btrim(coalesce(e.result_status, ''''))) not in (' || chr(10) ||
    '          ''no show'', ''no_show'', ''noshow'', ''disqualified'', ''dq'',' || chr(10) ||
    '          ''unworthy of award'', ''unworthy''' || chr(10) ||
    '        )';
  v_legs_needle text :=
    '        and e.exhibitor_id = ex.id and e.is_shown = true' || chr(10) ||
    '        and e.scratched_at is null' || chr(10) ||
    '        and ea.award_code in (';
  v_legs_replacement text :=
    '        and e.exhibitor_id = ex.id and e.is_shown = true' || chr(10) ||
    '        and e.scratched_at is null' || chr(10) ||
    '        and coalesce(e.is_disqualified, false) = false' || chr(10) ||
    '        and coalesce(e.is_test, false) = false' || chr(10) ||
    '        and lower(coalesce(e.status, '''')) not in (' || chr(10) ||
    '          ''deleted'', ''cancelled'', ''canceled'', ''scratched''' || chr(10) ||
    '        )' || chr(10) ||
    '        and lower(btrim(coalesce(e.result_status, ''''))) not in (' || chr(10) ||
    '          ''no show'', ''no_show'', ''noshow'', ''disqualified'', ''dq'',' || chr(10) ||
    '          ''unworthy of award'', ''unworthy''' || chr(10) ||
    '        )' || chr(10) ||
    '        and ea.award_code in (';
begin
  select pg_get_functiondef(p.oid)
  into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'finalize_show_scoped'
    and p.proargtypes = '2950 2951 25 25'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception
      'public.finalize_show_scoped(uuid, uuid[], text, text) is required';
  end if;

  if (
    length(v_definition) - length(replace(v_definition, v_exhibitor_needle, ''))
  ) / length(v_exhibitor_needle) <> 1 then
    raise exception
      'Expected one exhibitor artifact eligibility predicate in finalize_show_scoped';
  end if;

  if (
    length(v_definition) - length(replace(v_definition, v_legs_needle, ''))
  ) / length(v_legs_needle) <> 1 then
    raise exception
      'Expected one legs artifact eligibility predicate in finalize_show_scoped';
  end if;

  v_definition := replace(
    v_definition,
    v_exhibitor_needle,
    v_exhibitor_replacement
  );
  v_definition := replace(
    v_definition,
    v_legs_needle,
    v_legs_replacement
  );
  execute v_definition;
end;
$block$;

comment on function public.finalize_show_scoped(uuid, uuid[], text, text)
is 'Finalizes selected enabled sections using scoped readiness and canonical exhibitor eligibility for all queued artifacts.';
