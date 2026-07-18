-- Keep deferred ARBA artifacts out of automatic generation progress while
-- surfacing actionable ARBA validation warnings in Reports Needing Review.

alter function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) rename to get_closeout_dashboard_scoped_without_actionable_arba_review;

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
  v_run_id uuid;
  v_arba_review jsonb := '[]'::jsonb;
begin
  v_dashboard := public.get_closeout_dashboard_scoped_without_actionable_arba_review(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );

  v_run_id := nullif(v_dashboard -> 'latest_finalize' ->> 'id', '')::uuid;

  if v_run_id is not null then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'artifact_id', a.id,
          'finalize_run_id', a.finalize_run_id,
          'report_name', a.report_name,
          'artifact_status', a.artifact_status,
          'task_status', 'missing',
          'review_group', 'non_retryable_failure',
          'section_ids', to_jsonb(a.section_ids),
          'section_id', a.metadata ->> 'section_id',
          'section_label', a.metadata ->> 'section_label',
          'show_letter', a.metadata ->> 'show_letter',
          'scope', a.metadata ->> 'scope',
          'error_category', 'missing_sanction_number',
          'error_message', coalesce(
            nullif(a.metadata ->> 'last_error', ''),
            nullif(a.metadata ->> 'error_message', ''),
            'This ARBA report needs required information before it can be generated.'
          ),
          'metadata', a.metadata || jsonb_build_object(
            'error_category', 'missing_sanction_number'
          ),
          'metadata_last_error', a.metadata ->> 'last_error',
          'metadata_error_message', a.metadata ->> 'error_message',
          'metadata_error_category', 'missing_sanction_number',
          'retryable', false,
          'attempt_count', 0,
          'max_attempts', 0,
          'last_attempted_at', null
        )
        order by a.metadata ->> 'section_label', a.id
      ),
      '[]'::jsonb
    )
    into v_arba_review
    from public.show_report_artifacts a
    where a.show_id = p_show_id
      and a.finalize_run_id = v_run_id
      and a.is_current = true
      and a.report_name = 'arba_report'::public.report_type
      and a.artifact_status = 'warning'::public.artifact_status
      and coalesce(
        nullif(a.metadata ->> 'last_error', ''),
        nullif(a.metadata ->> 'error_message', ''),
        nullif(a.metadata ->> 'error_category', '')
      ) is not null;
  end if;

  return jsonb_set(
    v_dashboard,
    '{review_reports}',
    coalesce(v_dashboard -> 'review_reports', '[]'::jsonb) || v_arba_review,
    true
  );
end;
$function$;

revoke all on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;

revoke all on function public.get_closeout_dashboard_scoped_without_actionable_arba_review(
  uuid, text, uuid[], integer, integer, public.report_type
) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped_without_actionable_arba_review(
  uuid, text, uuid[], integer, integer, public.report_type
) to authenticated, service_role;

comment on function public.get_closeout_dashboard_scoped(
  uuid, text, uuid[], integer, integer, public.report_type
)
is 'Returns scoped Closeout progress plus actionable deferred ARBA validation warnings for Reports Needing Review.';
