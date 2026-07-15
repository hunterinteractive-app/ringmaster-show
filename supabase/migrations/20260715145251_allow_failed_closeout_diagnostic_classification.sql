-- Failed legacy artifacts may retain noncanonical scope only while they remain
-- current, failed review records and only diagnostic metadata changes. Every
-- insert, status transition, or identity/scope change still uses the canonical
-- resolver.
create or replace function public.set_closeout_artifact_scope_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_scope record;
  v_diagnostic_only boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_diagnostic_only :=
      old.artifact_status = 'failed'::public.artifact_status
      and new.artifact_status = 'failed'::public.artifact_status
      and old.is_current = true
      and new.is_current = true
      and old.show_id is not distinct from new.show_id
      and old.finalize_run_id is not distinct from new.finalize_run_id
      and old.report_name is not distinct from new.report_name
      and old.section_ids is not distinct from new.section_ids
      and old.scope_key is not distinct from new.scope_key
      and old.artifact_key is not distinct from new.artifact_key
      and (
        old.metadata - array[
          'error_category',
          'error_message',
          'retryable',
          'non_retryable_reason'
        ]::text[]
      ) is not distinct from (
        new.metadata - array[
          'error_category',
          'error_message',
          'retryable',
          'non_retryable_reason'
        ]::text[]
      );

    if v_diagnostic_only then
      -- The obsolete item remains a failed current review record. Do not try
      -- to invent scope for an exhibitor with no qualifying entries.
      if new.metadata ->> 'error_category' = 'missing_exhibitor_entries' then
        new.metadata := new.metadata || jsonb_build_object(
          'retryable', false,
          'non_retryable_reason', 'missing_exhibitor_entries'
        );
      end if;
    end if;
  end if;

  if new.finalize_run_id is not null and not v_diagnostic_only then
    if tg_op = 'UPDATE'
       and old.show_id = new.show_id
       and old.finalize_run_id = new.finalize_run_id
       and old.report_name = new.report_name
       and old.artifact_key = public.closeout_artifact_identity(
         new.report_name, new.metadata
       )
       and old.scope_key = public.closeout_artifact_scope_key(
         old.show_id, old.report_name, old.section_ids, old.metadata
       ) then
      new.scope_key := old.scope_key;
      new.section_ids := old.section_ids;
      new.artifact_key := old.artifact_key;
      new.metadata := new.metadata || jsonb_build_object(
        'scope_key', old.scope_key,
        'section_ids', to_jsonb(old.section_ids),
        'run_scope_key', old.metadata ->> 'run_scope_key'
      );
    else
      select * into v_scope
      from public.resolve_closeout_artifact_scope(
        new.show_id, new.finalize_run_id, new.report_name, new.metadata
      );
      if not coalesce(v_scope.is_repairable, false) then
        raise exception 'Cannot derive canonical closeout artifact scope: %',
          coalesce(v_scope.failure_reason, 'unknown_scope');
      end if;
      new.scope_key := v_scope.scope_key;
      new.section_ids := v_scope.section_ids;
      new.metadata := v_scope.metadata;
      new.artifact_key := v_scope.artifact_key;
    end if;
  end if;

  if new.finalize_run_id is not null and new.id is not null then
    new.storage_bucket := coalesce(nullif(new.storage_bucket, ''), 'show-files');
    new.storage_path := coalesce(nullif(new.storage_path, ''), format(
      'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
      new.show_id, new.finalize_run_id, new.id, new.generation
    ));
  end if;
  return new;
end;
$function$;

drop trigger if exists set_closeout_artifact_scope_columns
  on public.show_report_artifacts;
create trigger set_closeout_artifact_scope_columns
before insert or update of
  metadata,
  scope_key,
  section_ids,
  artifact_key,
  finalize_run_id,
  report_name,
  show_id,
  artifact_status
on public.show_report_artifacts
for each row execute function public.set_closeout_artifact_scope_columns();

comment on function public.set_closeout_artifact_scope_columns()
is 'Enforces canonical Closeout scope except for diagnostic-only updates to current failed artifacts; obsolete missing-entry reports remain non-retryable review records.';

revoke all on function public.set_closeout_artifact_scope_columns()
  from public, anon, authenticated;
