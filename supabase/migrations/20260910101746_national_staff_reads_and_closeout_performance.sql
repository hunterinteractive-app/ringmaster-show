create or replace function public.get_show_checkin_roster(
  p_show_id uuid,
  p_search text default '',
  p_status text default 'all'
)
returns table (
  exhibitor_id uuid,
  exhibitor_name text,
  exhibitor_number text,
  checkin_status text,
  completed_at timestamptz,
  balance_due_cents integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_status text := lower(btrim(coalesce(p_status, 'all')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in roster.' using errcode = '42501';
  end if;
  if v_status not in ('all', 'balance_due', 'not_started', 'in_progress', 'completed', 'reviewed_by_secretary', 'locked') then
    raise exception 'Invalid check-in status.' using errcode = '22023';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    coalesce(r.status, 'not_started'),
    r.completed_at,
    coalesce(balance_summary.total_due_cents, 0)::integer
  from (select distinct entry.exhibitor_id from public.entries entry
        where entry.show_id = p_show_id) e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id
  left join (
    select b.exhibitor_id, sum(b.balance_due_cents)::integer as total_due_cents
    from public.show_exhibitor_balances b
    where b.show_id = p_show_id
    group by b.exhibitor_id
  ) balance_summary on balance_summary.exhibitor_id = e.exhibitor_id
  where true
    and (v_status = 'all' or v_status = 'balance_due' or coalesce(r.status, 'not_started') = v_status)
    and (v_status <> 'balance_due' or coalesce(balance_summary.total_due_cents, 0) > 0)
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  order by coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))), e.exhibitor_id;
end;
$$;

create or replace function public.report_results_entry_rows_page(
  p_show_id uuid,
  p_section_id uuid default null,
  p_show_letter text default null,
  p_breed text default null,
  p_entry_ids uuid[] default null,
  p_after_entry_id uuid default null,
  p_page_size integer default 1000
)
returns table(
  entry_id uuid,
  section_id uuid,
  exhibitor_id uuid,
  exhibitor_label text,
  exhibitor_number text,
  exhibitor_showing_name text,
  exhibitor_first_name text,
  exhibitor_last_name text,
  exhibitor_address_line1 text,
  exhibitor_address_line2 text,
  exhibitor_city text,
  exhibitor_state text,
  exhibitor_zip text,
  breed text,
  breed_id uuid,
  breed_name text,
  variety text,
  variety_name text,
  fur_variety text,
  group_name text,
  class_name text,
  sex text,
  tattoo text,
  placement text,
  result_status text,
  is_shown boolean,
  is_disqualified boolean,
  disqualified_reason text,
  scratched_at timestamptz,
  judged_by_show_judge_id uuid,
  is_fur boolean,
  uses_group_awards boolean,
  uses_variety_awards boolean,
  breed_sort_order integer,
  group_sort_order integer,
  variety_sort_order integer,
  class_sort_order integer
)
language sql
stable
security definer
set search_path = ''
as $$
with page_entries as materialized (
  select e.* from public.entries e
  left join public.show_sections s on s.id = e.section_id
  where e.show_id = p_show_id
    and (p_section_id is null or e.section_id = p_section_id)
    and (p_show_letter is null or p_show_letter = '' or upper(coalesce(s.letter::text, '')) = upper(p_show_letter))
    and (p_breed is null or lower(btrim(e.breed)) = lower(btrim(p_breed)))
    and (p_entry_ids is null or e.id = any(p_entry_ids))
    and (p_after_entry_id is null or e.id > p_after_entry_id)
  order by e.id
  limit greatest(1, least(coalesce(p_page_size, 1000), 1000))
)
select distinct on (e.id)
  e.id as entry_id,
  e.section_id,
  e.exhibitor_id,
  coalesce(
    nullif(ex.display_name, ''),
    nullif(ex.showing_name, ''),
    nullif(trim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
    ''
  )::text as exhibitor_label,
  coalesce(ex.exhibitor_number::text, sen.exhibitor_number::text, '')::text as exhibitor_number,
  coalesce(ex.showing_name, '')::text as exhibitor_showing_name,
  coalesce(ex.first_name, '')::text as exhibitor_first_name,
  coalesce(ex.last_name, '')::text as exhibitor_last_name,
  coalesce(ex.address_line1, '')::text as exhibitor_address_line1,
  coalesce(ex.address_line2, '')::text as exhibitor_address_line2,
  coalesce(ex.city, '')::text as exhibitor_city,
  coalesce(ex.state, '')::text as exhibitor_state,
  coalesce(ex.zip, '')::text as exhibitor_zip,
  coalesce(e.breed, '')::text as breed,
  b.id as breed_id,
  coalesce(b.name, e.breed, '')::text as breed_name,
  coalesce(e.variety, '')::text as variety,
  coalesce(v.name, e.variety, '')::text as variety_name,
  coalesce(e.fur_variety, '')::text as fur_variety,
  case when coalesce(e.is_fur, false) then 'Fur / Wool' else coalesce(vg.name, '')::text end::text as group_name,
  coalesce(e.class_name, '')::text as class_name,
  coalesce(e.sex, '')::text as sex,
  coalesce(e.tattoo, '')::text as tattoo,
  case when coalesce(e.is_fur, false) then e.fur_placement::text else e.placement::text end as placement,
  case
    when lower(coalesce(e.result_status, '')) like 'disqualified%' then e.result_status::text
    when coalesce(e.is_disqualified, false) then ('Disqualified - ' || coalesce(nullif(trim(e.disqualified_reason), ''), 'Other'))::text
    else coalesce(e.result_status, 'Shown')::text
  end as result_status,
  case
    when e.scratched_at is not null then false
    when coalesce(e.is_fur, false) then coalesce(e.is_shown, true)
    else coalesce(e.is_shown, true)
  end::boolean as is_shown,
  coalesce(e.is_disqualified, false)::boolean as is_disqualified,
  coalesce(e.disqualified_reason, '')::text as disqualified_reason,
  e.scratched_at,
  e.judged_by_show_judge_id,
  coalesce(e.is_fur, false)::boolean as is_fur,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_group_awards, false) end::boolean as uses_group_awards,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_variety_awards, false) end::boolean as uses_variety_awards,
  0::integer as breed_sort_order,
  case when coalesce(e.is_fur, false) then 9999 when vg.id is null then 9998 else coalesce(vg.sort_order, 9998)::integer end as group_sort_order,
  case when coalesce(e.is_fur, false) then 9999 else coalesce(v.sort_order, 9999)::integer end as variety_sort_order,
  case
    when coalesce(e.is_fur, false) then 1000
    when lower(coalesce(e.class_name, '')) like '%senior%' then 0
    when lower(coalesce(e.class_name, '')) like '%intermediate%' then 1
    when lower(coalesce(e.class_name, '')) like '%junior%' then 2
    else 99
  end::integer as class_sort_order
from page_entries e
left join public.exhibitors ex on ex.id = e.exhibitor_id
left join lateral (
  select sen.* from public.show_exhibitor_numbers sen
  where sen.show_id = e.show_id and sen.exhibitor_id = e.exhibitor_id
  order by sen.exhibitor_number nulls last, sen.id limit 1
) sen on true
left join lateral (
  select b.* from public.breeds b
  where b.is_active = true
    and lower(trim(b.name)) = lower(trim(e.breed))
    and lower(b.species::text) = lower(e.species::text)
  order by b.name, b.id limit 1
) b on true
left join lateral (
  select v.* from public.varieties v
  where v.breed_id = b.id and lower(trim(v.name)) = lower(trim(e.variety))
  order by v.sort_order nulls last, v.name, v.id limit 1
) v on true
left join public.variety_groups vg on vg.id = v.group_id
left join public.show_sections s on s.id = e.section_id
where e.show_id = p_show_id
  and (p_breed is null or lower(btrim(e.breed)) = lower(btrim(p_breed)))
  and (p_section_id is null or e.section_id = p_section_id)
  and (p_show_letter is null or p_show_letter = '' or upper(coalesce(s.letter::text, '')) = upper(p_show_letter))
order by e.id, breed, group_sort_order, group_name, variety_sort_order, variety, class_sort_order, sex, tattoo;
$$;

-- Active work belongs in progress counts; keep review rows actionable.
CREATE OR REPLACE FUNCTION public.get_closeout_dashboard_scoped_without_error_sources(p_show_id uuid, p_scope_key text, p_section_ids uuid[], p_artifact_limit integer DEFAULT 100, p_artifact_offset integer DEFAULT 0, p_report_name report_type DEFAULT NULL::report_type)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_dashboard jsonb;
  v_last_activity_at timestamptz;
  v_completed_at timestamptz;
  v_active_count integer := 0;
  v_review_reports jsonb := '[]'::jsonb;
  v_skipped_count integer := 0;
  v_skipped_reports jsonb := '[]'::jsonb;
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
    where (
      a.artifact_status in (
        'queued'::public.artifact_status,
        'failed'::public.artifact_status
      )
      or q.task_status in (
        'queued'::public.show_task_status,
        'running'::public.show_task_status,
        'failed'::public.show_task_status
      )
    )
    and coalesce(q.task_status not in ('queued', 'running'), true)
    and coalesce(a.metadata ->> 'error_category', '') <> 'missing_exhibitor_entries'
    and coalesce(a.metadata ->> 'non_retryable_reason', '') <> 'missing_exhibitor_entries'
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

  with selected_run as (
    select f.id
    from public.show_finalize_runs f
    where f.show_id = p_show_id
      and f.scope_key = p_scope_key
      and f.section_ids = p_section_ids
    order by f.started_at desc
    limit 1
  ),
  skipped as (
    select a.*
    from public.show_report_artifacts a
    join selected_run r on r.id = a.finalize_run_id
    where a.show_id = p_show_id
      and a.is_current = true
      and a.artifact_status = 'failed'::public.artifact_status
      and (
        a.metadata ->> 'error_category' = 'missing_exhibitor_entries'
        or a.metadata ->> 'non_retryable_reason' = 'missing_exhibitor_entries'
      )
  )
  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'artifact_id', s.id,
          'report_name', s.report_name,
          'exhibitor_id', s.metadata ->> 'exhibitor_id',
          'exhibitor_name', s.metadata ->> 'exhibitor_name',
          'reason', 'No qualifying shown entries'
        )
        order by s.metadata ->> 'exhibitor_name', s.id
      ),
      '[]'::jsonb
    )
  into v_skipped_count, v_skipped_reports
  from skipped s;

  v_dashboard := jsonb_set(
    v_dashboard,
    '{task_counts}',
    coalesce(v_dashboard -> 'task_counts', '{}'::jsonb) ||
      jsonb_build_object(
        'failed',
          greatest(
            coalesce((v_dashboard -> 'task_counts' ->> 'failed')::integer, 0)
              - v_skipped_count,
            0
          ),
        'remaining',
          greatest(
            coalesce((v_dashboard -> 'task_counts' ->> 'remaining')::integer, 0)
              - v_skipped_count,
            0
          ),
        'skipped_reports', v_skipped_count,
        'skipped_missing_exhibitor_entries', v_skipped_count,
        'last_activity_at', v_last_activity_at,
        'completed_at', case when v_active_count = 0 then v_completed_at end
      ),
    true
  );

  v_dashboard := jsonb_set(
    v_dashboard,
    '{skipped_reports}',
    v_skipped_reports,
    true
  );

  return jsonb_set(
    v_dashboard,
    '{review_reports}',
    v_review_reports,
    true
  );
end;
$function$
;

-- Check show permission once, then run the read-only scoped queries.
CREATE OR REPLACE FUNCTION public.get_closeout_dashboard_scoped(p_show_id uuid, p_scope_key text, p_section_ids uuid[], p_artifact_limit integer DEFAULT 100, p_artifact_offset integer DEFAULT 0, p_report_name report_type DEFAULT NULL::report_type)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 STABLE
 SET search_path TO ''
AS $function$
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not (session_user = 'postgres' and current_setting('role') in ('none', 'postgres'))
     and not coalesce(public.user_can_finalize_show(p_show_id, auth.uid()), false) then
    raise exception 'Not authorized to manage closeout for this show' using errcode = '42501';
  end if;
  return public.get_closeout_dashboard_scoped_without_readiness_details(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.get_closeout_dashboard_scoped_for_species(p_show_id uuid, p_scope_key text, p_section_ids uuid[], p_artifact_limit integer DEFAULT 100, p_artifact_offset integer DEFAULT 0, p_report_name report_type DEFAULT NULL::report_type, p_species_filter text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_species text := nullif(lower(btrim(coalesce(p_species_filter, ''))), '');
  v_dashboard jsonb;
  v_run_id uuid;
  v_reports jsonb := '[]'::jsonb;
  v_review_reports jsonb := '[]'::jsonb;
  v_artifact_counts jsonb := '{}'::jsonb;
  v_task_counts jsonb := '{}'::jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and not (session_user = 'postgres' and current_setting('role') in ('none', 'postgres'))
     and not coalesce(public.user_can_finalize_show(p_show_id, auth.uid()), false) then
    raise exception 'Not authorized to manage closeout for this show' using errcode = '42501';
  end if;
  if v_species is not null and v_species not in ('rabbit', 'cavy') then
    raise exception 'Unsupported closeout species filter: %', p_species_filter;
  end if;

  v_dashboard := public.get_closeout_dashboard_scoped(
    p_show_id,
    p_scope_key,
    p_section_ids,
    p_artifact_limit,
    p_artifact_offset,
    p_report_name
  );
  if v_species is null then
    return v_dashboard;
  end if;

  v_run_id := nullif(v_dashboard -> 'latest_finalize' ->> 'id', '')::uuid;
  if v_run_id is null then
    return v_dashboard;
  end if;

  select coalesce(jsonb_agg(to_jsonb(page) order by page.report_name, page.created_at, page.id), '[]'::jsonb)
  into v_reports
  from (
    select a.* from public.show_report_artifacts a
    where a.show_id = p_show_id and a.finalize_run_id = v_run_id and a.is_current
      and (p_report_name is null or a.report_name = p_report_name)
      and (lower(a.metadata ->> 'species') = v_species or coalesce(a.metadata -> 'species', '[]'::jsonb) ? v_species)
    order by a.report_name, a.created_at, a.id
    limit greatest(1, least(coalesce(p_artifact_limit, 100), 200))
    offset greatest(0, coalesce(p_artifact_offset, 0))
  ) page;
  v_dashboard := jsonb_set(v_dashboard, '{artifact_page,has_more}', to_jsonb((
    select count(*) from public.show_report_artifacts a
    where a.show_id = p_show_id and a.finalize_run_id = v_run_id and a.is_current
      and (p_report_name is null or a.report_name = p_report_name)
      and (lower(a.metadata ->> 'species') = v_species or coalesce(a.metadata -> 'species', '[]'::jsonb) ? v_species)
  ) > greatest(0, coalesce(p_artifact_offset, 0)) + greatest(1, least(coalesce(p_artifact_limit, 100), 200))), true);

  select coalesce(jsonb_agg(review.value order by review.ordinality), '[]'::jsonb)
  into v_review_reports
  from jsonb_array_elements(
    coalesce(v_dashboard -> 'review_reports', '[]'::jsonb)
  ) with ordinality review(value, ordinality)
  where (lower(coalesce(
    review.value ->> 'species',
    review.value -> 'metadata' ->> 'species',
    ''
  )) = v_species or coalesce(review.value -> 'metadata' -> 'species', '[]'::jsonb) ? v_species);

  select jsonb_build_object(
    'total', count(*)::integer,
    'generated', count(*) filter (
      where a.artifact_status = 'generated'
    )::integer,
    'queued', count(*) filter (
      where a.artifact_status = 'queued'
    )::integer,
    'failed', count(*) filter (
      where a.artifact_status = 'failed'
    )::integer,
    'by_report', coalesce((
      select jsonb_object_agg(grouped.report_name, grouped.report_count)
      from (
        select species_artifact.report_name, count(*)::integer report_count
        from public.show_report_artifacts species_artifact
        where species_artifact.finalize_run_id = v_run_id
          and species_artifact.is_current = true
          and species_artifact.report_name <> 'arba_report'::public.report_type
          and (lower(species_artifact.metadata ->> 'species') = v_species or coalesce(species_artifact.metadata -> 'species', '[]'::jsonb) ? v_species)
          and (p_report_name is null or species_artifact.report_name = p_report_name)
        group by species_artifact.report_name
      ) grouped
    ), '{}'::jsonb)
  )
  into v_artifact_counts
  from public.show_report_artifacts a
  where a.finalize_run_id = v_run_id
    and a.is_current = true
    and a.report_name <> 'arba_report'::public.report_type
    and (lower(a.metadata ->> 'species') = v_species or coalesce(a.metadata -> 'species', '[]'::jsonb) ? v_species)
    and (p_report_name is null or a.report_name = p_report_name);

  with species_artifacts as (
    select a.id, a.artifact_status
    from public.show_report_artifacts a
    where a.finalize_run_id = v_run_id
      and a.is_current = true
      and a.report_name <> 'arba_report'::public.report_type
      and (lower(a.metadata ->> 'species') = v_species or coalesce(a.metadata -> 'species', '[]'::jsonb) ? v_species)
      and (p_report_name is null or a.report_name = p_report_name)
  ), counts as (
    select
      count(*) filter (where q.task_status = 'queued')::integer queued,
      count(*) filter (where q.task_status = 'running')::integer running,
      count(*) filter (where q.task_status = 'failed')::integer failed,
      count(*) filter (where q.task_status = 'completed')::integer completed,
      count(*) filter (
        where q.task_status = 'failed'
          and q.attempt_count < q.max_attempts
      )::integer retryable_failed,
      max(coalesce(
        q.completed_at,
        q.failed_at,
        q.heartbeat_at,
        q.claimed_at,
        q.started_at,
        q.created_at
      )) last_activity_at,
      max(q.completed_at) completed_at
    from public.show_task_queue q
    join species_artifacts a on a.id = q.report_artifact_id
    where q.task_type = 'render_report'::public.show_task_type
  ), missing as (
    select count(*)::integer missing_count
    from species_artifacts a
    where a.artifact_status in ('queued', 'failed')
      and not exists (
        select 1
        from public.show_task_queue q
        where q.report_artifact_id = a.id
          and q.task_type = 'render_report'::public.show_task_type
      )
  )
  select jsonb_build_object(
    'queued', coalesce(c.queued, 0),
    'running', coalesce(c.running, 0),
    'failed', coalesce(c.failed, 0),
    'completed', coalesce(c.completed, 0),
    'retryable_failed', coalesce(c.retryable_failed, 0),
    'remaining', coalesce(c.retryable_failed, 0) + coalesce(m.missing_count, 0),
    'last_activity_at', c.last_activity_at,
    'completed_at', c.completed_at
  )
  into v_task_counts
  from counts c
  cross join missing m;

  v_dashboard := jsonb_set(v_dashboard, '{reports}', v_reports, true);
  v_dashboard := jsonb_set(
    v_dashboard, '{review_reports}', v_review_reports, true
  );
  v_dashboard := jsonb_set(
    v_dashboard, '{artifact_counts}', v_artifact_counts, true
  );
  v_dashboard := jsonb_set(v_dashboard, '{task_counts}', v_task_counts, true);
  v_dashboard := jsonb_set(
    v_dashboard,
    '{dashboard,closeout,reports_generated_count}',
    to_jsonb(coalesce((v_artifact_counts ->> 'generated')::integer, 0)),
    true
  );
  return v_dashboard;
end;
$function$
;

revoke all on function public.get_closeout_dashboard_scoped(uuid,text,uuid[],integer,integer,public.report_type) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped(uuid,text,uuid[],integer,integer,public.report_type) to authenticated, service_role;
revoke all on function public.get_closeout_dashboard_scoped_for_species(uuid,text,uuid[],integer,integer,public.report_type,text) from public, anon;
grant execute on function public.get_closeout_dashboard_scoped_for_species(uuid,text,uuid[],integer,integer,public.report_type,text) to authenticated, service_role;
create index if not exists closeout_current_artifact_page_idx
  on public.show_report_artifacts(finalize_run_id, report_name, created_at, id) where is_current;
create index if not exists closeout_render_artifact_task_idx
  on public.show_task_queue(report_artifact_id) where task_type = 'render_report';

create index if not exists entries_show_section_breed_page_idx
  on public.entries(show_id, section_id, lower(btrim(breed)), id);

-- Cursor pages remain complete when earlier exhibitors change check-in status.
create or replace function public.get_show_checkin_roster_page(
  p_show_id uuid,
  p_search text default '',
  p_status text default 'all',
  p_after_exhibitor_id uuid default null,
  p_page_size integer default 1000
)
returns table (
  exhibitor_id uuid,
  exhibitor_name text,
  exhibitor_number text,
  checkin_status text,
  completed_at timestamptz,
  balance_due_cents integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
  v_status text := lower(btrim(coalesce(p_status, 'all')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in roster.' using errcode = '42501';
  end if;
  if v_status not in ('all', 'balance_due', 'not_started', 'in_progress', 'completed', 'reviewed_by_secretary', 'locked') then
    raise exception 'Invalid check-in status.' using errcode = '22023';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    coalesce(r.status, 'not_started'),
    r.completed_at,
    coalesce(balance_summary.total_due_cents, 0)::integer
  from (select distinct entry.exhibitor_id from public.entries entry
        where entry.show_id = p_show_id) e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id
  left join (
    select b.exhibitor_id, sum(b.balance_due_cents)::integer as total_due_cents
    from public.show_exhibitor_balances b
    where b.show_id = p_show_id
    group by b.exhibitor_id
  ) balance_summary on balance_summary.exhibitor_id = e.exhibitor_id
  where (p_after_exhibitor_id is null or e.exhibitor_id > p_after_exhibitor_id)
    and (v_status = 'all' or v_status = 'balance_due' or coalesce(r.status, 'not_started') = v_status)
    and (v_status <> 'balance_due' or coalesce(balance_summary.total_due_cents, 0) > 0)
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  order by e.exhibitor_id
  limit greatest(1, least(coalesce(p_page_size, 1000), 1000));
end;
$$;
