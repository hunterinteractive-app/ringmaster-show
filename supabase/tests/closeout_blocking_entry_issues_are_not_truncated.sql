-- The closeout issue list must remain complete after PostgREST's default
-- 1,000-row response limit would have truncated a set-returning RPC.

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
)
select
  gen_random_uuid(),
  '20000000-0000-0000-0000-000000000004'::uuid,
  '21000000-0000-0000-0000-000000000004'::uuid,
  '30000000-0000-0000-0000-000000000001'::uuid,
  'rabbit',
  'ROW-CAP-' || series.number,
  'Large Closeout Regression',
  'Black',
  'Doe',
  'Senior',
  'entered',
  true,
  false,
  '0',
  'Shown'
from generate_series(1, 1001) as series(number);

select is(
  jsonb_typeof(
    public.show_results_blocking_entry_issues_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    )
  ),
  'object',
  'the RPC returns one JSON document instead of a row set'
);

select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.show_results_blocking_entry_issues_scoped(
        '20000000-0000-0000-0000-000000000004',
        array['21000000-0000-0000-0000-000000000004']::uuid[]
      ) -> 'items'
    ) item
    where item ->> 'issue_type' = 'missing_judge'
      and item ->> 'tattoo' like 'ROW-CAP-%'
  ),
  1001,
  'all issues beyond the API row limit remain visible'
);

select is(
  (
    public.show_results_blocking_entry_issues_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_judge_count'
  )::integer,
  (
    public.show_results_readiness_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    ) ->> 'missing_judge_count'
  )::integer,
  'Needs Fixed and report generation count the same missing judges'
);

select * from finish();
rollback;
