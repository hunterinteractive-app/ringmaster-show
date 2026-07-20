-- Some legacy failed artifacts were never classified with the structured
-- missing_exhibitor_entries marker. Derive whether an exhibitor-scoped artifact
-- still has qualifying entries before any regenerate/requeue update reaches the
-- canonical-scope validation trigger.
do $block$
declare
  v_definition text;
  v_needle text :=
    '    and coalesce(a.metadata ->> ''non_retryable_reason'', '''') <> ''missing_exhibitor_entries''';
  v_replacement text := v_needle || chr(10) ||
    '    and (' || chr(10) ||
    '      a.report_name not in (' || chr(10) ||
    '        ''exhibitor_report''::public.report_type,' || chr(10) ||
    '        ''checkin_sheet''::public.report_type,' || chr(10) ||
    '        ''legs''::public.report_type' || chr(10) ||
    '      )' || chr(10) ||
    '      or exists (' || chr(10) ||
    '        select 1' || chr(10) ||
    '        from public.entries eligible_entry' || chr(10) ||
    '        where eligible_entry.show_id = a.show_id' || chr(10) ||
    '          and eligible_entry.exhibitor_id::text = a.metadata ->> ''exhibitor_id''' || chr(10) ||
    '          and eligible_entry.section_id = any(a.section_ids)' || chr(10) ||
    '          and eligible_entry.is_shown = true' || chr(10) ||
    '          and eligible_entry.scratched_at is null' || chr(10) ||
    '          and coalesce(eligible_entry.is_disqualified, false) = false' || chr(10) ||
    '          and coalesce(eligible_entry.is_test, false) = false' || chr(10) ||
    '          and lower(coalesce(eligible_entry.status, '''')) not in (' || chr(10) ||
    '            ''deleted'', ''cancelled'', ''canceled'', ''scratched''' || chr(10) ||
    '          )' || chr(10) ||
    '          and lower(btrim(coalesce(eligible_entry.result_status, ''''))) not in (' || chr(10) ||
    '            ''no show'', ''no_show'', ''noshow'', ''disqualified'', ''dq'',' || chr(10) ||
    '            ''unworthy of award'', ''unworthy''' || chr(10) ||
    '          )' || chr(10) ||
    '      )' || chr(10) ||
    '    )';
  v_occurrences integer;
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'requeue_closeout_render_tasks_for_species'
    and p.proargtypes = '2950 2950 25 16 25'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception 'public.requeue_closeout_render_tasks_for_species is required';
  end if;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_needle, ''))
  ) / length(v_needle);
  if v_occurrences <> 4 then
    raise exception
      'Expected four obsolete-artifact marker filters, found %',
      v_occurrences;
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$block$;

comment on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
)
is 'Repairs and requeues canonical Closeout artifacts for an optional species while deriving and skipping obsolete exhibitor artifacts that have no qualifying shown entries.';
