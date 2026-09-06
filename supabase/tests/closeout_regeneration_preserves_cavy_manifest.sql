-- ACBA sanctions use the aggregate breed label "Cavy" while the entries use
-- their actual breeds. Regenerate All must retain both required club reports
-- for every sanctioned cavy section.

create extension if not exists pgtap with schema extensions;

begin;
select plan(10);

delete from public.show_sanctions
where show_id = '20000000-0000-0000-0000-000000000004'
  and section_id in (
    '21000000-0000-0000-0000-000000000006',
    '21000000-0000-0000-0000-000000000007'
  );

insert into public.show_sanctions (
  show_id,
  section_id,
  breed_name,
  club_name,
  sanction_number,
  sanctioning_body,
  sweepstakes_email
) values
  (
    '20000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000006',
    'Cavy',
    'Synthetic American Cavy Breeders Association',
    'ACBA-OPEN-B',
    'NATIONAL CLUB',
    'acba@example.test'
  ),
  (
    '20000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000007',
    'Cavy',
    'Synthetic American Cavy Breeders Association',
    'ACBA-YOUTH-B',
    'NATIONAL CLUB',
    'acba@example.test'
  );

insert into public.show_finalize_runs (
  id,
  show_id,
  run_status,
  results_version,
  scope_key,
  scope_label,
  section_ids,
  summary,
  started_at,
  completed_at
) values (
  'f5000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004',
  'completed',
  1,
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000006,21000000-0000-0000-0000-000000000007',
  'Cavy Open B + Youth B',
  array[
    '21000000-0000-0000-0000-000000000006',
    '21000000-0000-0000-0000-000000000007'
  ]::uuid[],
  jsonb_build_object('manifest_version', 2),
  now(),
  now()
);

select is(
  (
    select count(*)::integer
    from public.entries entry
    where entry.show_id = '20000000-0000-0000-0000-000000000004'
      and entry.section_id in (
        '21000000-0000-0000-0000-000000000006',
        '21000000-0000-0000-0000-000000000007'
      )
      and entry.is_shown = true
      and lower(btrim(entry.breed)) = 'cavy'
  ),
  0,
  'fixture entries retain individual cavy breed names'
);

create temporary table cavy_manifest_results(payload jsonb);
insert into cavy_manifest_results
select public.rebuild_closeout_club_report_manifest(
  '20000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000006,21000000-0000-0000-0000-000000000007',
  'cavy'
);

select is(
  (select (payload ->> 'expected_count')::integer
   from cavy_manifest_results),
  4,
  'aggregate Cavy sanctions produce two reports for each section'
);

select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000002'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' =
        'Synthetic American Cavy Breeders Association'
  ),
  4,
  'all four ACBA club artifacts remain current'
);

select is(
  (
    select count(distinct artifact.metadata ->> 'section_id')::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000002'
      and artifact.is_current = true
  ),
  2,
  'both sanctioned cavy sections are represented'
);

select is(
  (
    select count(distinct artifact.report_name)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000002'
      and artifact.is_current = true
  ),
  2,
  'both required club report types are represented'
);

select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000002'
      and artifact.is_current = true
      and artifact.metadata ->> 'species' = 'cavy'
      and artifact.metadata ->> 'breed_name' = 'Cavy'
  ),
  4,
  'rebuilt artifacts preserve Cavy species and aggregate breed metadata'
);

truncate cavy_manifest_results;
insert into cavy_manifest_results
select public.requeue_closeout_render_tasks_for_species(
  '20000000-0000-0000-0000-000000000004',
  'f5000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000004:21000000-0000-0000-0000-000000000006,21000000-0000-0000-0000-000000000007',
  true,
  'cavy'
);

select is(
  (select (payload #>> '{club_manifest,expected_count}')::integer
   from cavy_manifest_results),
  4,
  'Regenerate All rediscovers all aggregate Cavy club reports'
);

select is(
  (
    select count(*)::integer
    from public.show_report_artifacts artifact
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000002'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' =
        'Synthetic American Cavy Breeders Association'
  ),
  4,
  'Regenerate All does not drop or duplicate Cavy club artifacts'
);

select is(
  (
    select count(*)::integer
    from public.show_task_queue task
    join public.show_report_artifacts artifact
      on artifact.id = task.report_artifact_id
    where artifact.finalize_run_id =
      'f5000000-0000-0000-0000-000000000002'
      and artifact.is_current = true
      and artifact.metadata ->> 'club_name' =
        'Synthetic American Cavy Breeders Association'
      and task.task_status = 'queued'
  ),
  4,
  'all rebuilt Cavy club artifacts are queued for rendering'
);

select like(
  pg_catalog.pg_get_functiondef(
    'public.finalize_show_scoped(uuid,uuid[],text,text)'::regprocedure
  ),
  '%lower(btrim(coalesce(ss.breed_name, ''''))) = ''cavy''%',
  'first-time finalization also supports aggregate Cavy sanctions'
);

select * from finish();
rollback;
