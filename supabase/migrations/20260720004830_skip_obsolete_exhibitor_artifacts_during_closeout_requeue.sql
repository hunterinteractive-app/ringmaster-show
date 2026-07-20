-- Exhibitor-scoped artifacts can become obsolete after entries are scratched,
-- disqualified, or otherwise removed from the finalized scope. Those artifacts
-- are intentionally retained as non-retryable diagnostics. Regenerate All must
-- not transition them back to queued: the canonical-scope trigger rejects that
-- transition with missing_exhibitor_entries and aborts the entire requeue.
do $block$
declare
  v_definition text;
  v_needle text := '    and a.is_current = true';
  v_replacement text := v_needle || chr(10) ||
    '    and coalesce(a.metadata ->> ''error_category'', '''') <> ''missing_exhibitor_entries''' || chr(10) ||
    '    and coalesce(a.metadata ->> ''non_retryable_reason'', '''') <> ''missing_exhibitor_entries''';
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
      'Expected four current-artifact filters in requeue function, found %',
      v_occurrences;
  end if;

  execute replace(v_definition, v_needle, v_replacement);
end;
$block$;

comment on function public.requeue_closeout_render_tasks_for_species(
  uuid, uuid, text, boolean, text
)
is 'Repairs and requeues canonical Closeout artifacts for an optional species while skipping obsolete exhibitor artifacts with no qualifying shown entries.';
