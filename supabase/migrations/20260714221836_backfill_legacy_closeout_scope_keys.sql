with run_scopes as (
  select
    fr.id as finalize_run_id,
    fr.show_id,
    coalesce(
      array_agg(distinct section_id order by section_id)
        filter (where section_id is not null),
      '{}'::uuid[]
    ) as section_ids
  from public.show_finalize_runs fr
  left join public.show_report_artifacts a
    on a.finalize_run_id = fr.id
  left join lateral unnest(coalesce(a.section_ids, '{}'::uuid[]))
    as section_id on true
  where fr.scope_key is null or btrim(fr.scope_key) = ''
  group by fr.id, fr.show_id
),
resolved as (
  select
    finalize_run_id,
    show_id,
    section_ids,
    case
      when cardinality(section_ids) > 0 then
        show_id::text || ':' ||
        array_to_string(section_ids, ',')
      else
        show_id::text || ':legacy:' || finalize_run_id::text
    end as scope_key
  from run_scopes
)
update public.show_finalize_runs fr
set
  scope_key = r.scope_key,
  scope_label = coalesce(
    nullif(btrim(fr.scope_label), ''),
    'Legacy Closeout'
  ),
  section_ids = case
    when cardinality(coalesce(fr.section_ids, '{}'::uuid[])) = 0
      then r.section_ids
    else fr.section_ids
  end
from resolved r
where fr.id = r.finalize_run_id;

update public.show_report_artifacts a
set scope_key = fr.scope_key
from public.show_finalize_runs fr
where a.finalize_run_id = fr.id
  and (a.scope_key is null or btrim(a.scope_key) = '');

update public.show_task_queue q
set scope_key = a.scope_key
from public.show_report_artifacts a
where q.report_artifact_id = a.id
  and q.task_type = 'render_report'::public.show_task_type
  and (q.scope_key is null or btrim(q.scope_key) = '');
