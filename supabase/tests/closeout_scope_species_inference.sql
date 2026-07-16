-- Transactional regression for sanctioned breed names that do not exactly
-- match the master breed spelling inside a mixed-species section.

create extension if not exists pgtap with schema extensions;

begin;
select plan(7);

insert into public.show_finalize_runs (
  id, show_id, run_status, scope_key, scope_label, section_ids, summary
) values (
  'f4000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000004',
  'completed', 'species-inference', 'Species inference',
  array['21000000-0000-0000-0000-000000000004']::uuid[], '{}'::jsonb
);

insert into public.entries (
  id, show_id, section_id, exhibitor_id, species, tattoo, animal_name,
  breed, variety, sex, class_name, status, is_shown, is_fur
) values (
  '40000000-0000-0000-0000-000000000099',
  '20000000-0000-0000-0000-000000000004',
  '21000000-0000-0000-0000-000000000004',
  '30000000-0000-0000-0000-000000000001',
  'cavy', 'C99', 'Mixed section cavy', 'Synthetic Cavy', 'Black',
  'Boar', 'Senior Boar', 'entered', true, false
);

create temporary table resolved as
select * from public.resolve_closeout_artifact_scope(
  '20000000-0000-0000-0000-000000000004',
  'f4000000-0000-0000-0000-000000000001',
  'sweepstakes_report'::public.report_type,
  jsonb_build_object(
    'section_id', '21000000-0000-0000-0000-000000000004',
    'scope', 'OPEN', 'show_letter', 'A',
    'breed_name', 'Canonical Name Missing From Breeds',
    'club_name', 'Synthetic Rabbit Federation'
  )
);

select ok((select is_repairable from resolved),
          'unambiguous rabbit club resolves in a mixed-species section');
select is((select metadata ->> 'species' from resolved), 'rabbit',
          'rabbit club token supplies canonical species');
select ok((select artifact_key like '%|rabbit|%' from resolved),
          'resolved identity includes inferred rabbit species');

truncate resolved;
insert into resolved
select * from public.resolve_closeout_artifact_scope(
  '20000000-0000-0000-0000-000000000004',
  'f4000000-0000-0000-0000-000000000001',
  'sweepstakes_report'::public.report_type,
  jsonb_build_object(
    'section_id', '21000000-0000-0000-0000-000000000004',
    'scope', 'OPEN', 'show_letter', 'A',
    'breed_name', 'Canonical Name Missing From Breeds',
    'club_name', 'Synthetic Cavy Club'
  )
);

select ok((select is_repairable from resolved),
          'unambiguous cavy club resolves in a mixed-species section');
select is((select metadata ->> 'species' from resolved), 'cavy',
          'cavy club token supplies canonical species');

truncate resolved;
insert into resolved
select * from public.resolve_closeout_artifact_scope(
  '20000000-0000-0000-0000-000000000004',
  'f4000000-0000-0000-0000-000000000001',
  'sweepstakes_report'::public.report_type,
  jsonb_build_object(
    'section_id', '21000000-0000-0000-0000-000000000004',
    'scope', 'OPEN', 'show_letter', 'A',
    'breed_name', 'Canonical Name Missing From Breeds',
    'club_name', 'Synthetic All Species Club'
  )
);

select ok(not (select is_repairable from resolved),
          'null species is rejected when mixed section remains ambiguous');
select is((select failure_reason from resolved), 'ambiguous_species',
          'ambiguous mixed-section species has an explicit failure reason');

select * from finish();
rollback;
