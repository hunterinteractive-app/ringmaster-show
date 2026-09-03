-- Placement 0 means the animal was judged but did not place. Multiple zeroes
-- in one class must not block closeout, while duplicate positive ranks must.

create extension if not exists pgtap with schema extensions;

begin;
select plan(3);

insert into public.entries (
  id,
  show_id,
  section_id,
  exhibitor_id,
  species,
  tattoo,
  breed,
  variety,
  sex,
  class_name,
  status,
  is_shown,
  is_fur,
  placement,
  result_status
) values
  (
    '40000000-0000-0000-0000-000000000201',
    '20000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000004',
    '30000000-0000-0000-0000-000000000001',
    'rabbit', 'ZERO-1', 'Zero Placement Regression', 'Black',
    'Doe', 'Senior', 'entered', true, false, '0', 'Shown'
  ),
  (
    '40000000-0000-0000-0000-000000000202',
    '20000000-0000-0000-0000-000000000004',
    '21000000-0000-0000-0000-000000000004',
    '30000000-0000-0000-0000-000000000001',
    'rabbit', 'ZERO-2', 'Zero Placement Regression', 'Black',
    'Doe', 'Senior', 'entered', true, false, '0', 'Shown'
  );

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_placement_count'
  )::integer,
  0,
  'placement zero still records that judging is complete'
);

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'duplicate_placement_group_count'
  )::integer,
  0,
  'multiple unplaced zeroes do not form a duplicate rank'
);

update public.entries
set placement = '1'
where id in (
  '40000000-0000-0000-0000-000000000201',
  '40000000-0000-0000-0000-000000000202'
);

select is(
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'duplicate_placement_group_count'
  )::integer,
  1,
  'duplicate positive placements remain blocking'
);

select * from finish();
rollback;
