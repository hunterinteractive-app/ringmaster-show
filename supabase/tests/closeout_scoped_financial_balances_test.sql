\set ON_ERROR_STOP on

create or replace function pg_temp.assert_true(value boolean, message text)
returns void language plpgsql as $$
begin
  if value is distinct from true then raise exception '%', message; end if;
end $$;

truncate public.legacy_balance_fixture;
insert into public.legacy_balance_fixture(value) values (jsonb_build_object(
  'balance_id', '30000000-0000-0000-0000-000000000001',
  'exhibitor_id', '40000000-0000-0000-0000-000000000001',
  'entry_count', 3,
  'fur_count', 1,
  'entries_subtotal_cents', 3000,
  'fur_subtotal_cents', 300,
  'show_fee_subtotal_cents', 700,
  'subtotal_before_discount_cents', 4000,
  'discount_cents', 0,
  'calculated_total_cents', 4000,
  'paid_online_cents', 0,
  'paid_manual_cents', 0,
  'refunded_cents', 0,
  'balance_due_cents', 4000,
  'payment_status', 'unpaid',
  'section_breakdown', jsonb_build_array(
    jsonb_build_object(
      'section_id', '20000000-0000-0000-0000-000000000001',
      'kind', 'open', 'letter', 'A', 'label', 'Rabbit Open A',
      'entry_count', 2, 'fur_count', 1,
      'entries_subtotal_cents', 2000, 'fur_subtotal_cents', 300,
      'show_fee_cents', 400
    ),
    jsonb_build_object(
      'section_id', '20000000-0000-0000-0000-000000000002',
      'kind', 'youth', 'letter', 'A', 'label', 'Cavy Youth A',
      'entry_count', 1, 'fur_count', 0,
      'entries_subtotal_cents', 1000, 'fur_subtotal_cents', 0,
      'show_fee_cents', 300
    )
  )
));

do $$
declare entire jsonb; scoped jsonb; duplicate_scope jsonb;
begin
  select value into entire
  from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001',
    array['20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002']::uuid[]
  ) value;
  perform pg_temp.assert_true(entire ->> 'payment_allocation_status' = 'exact_entire_show', 'entire show was not exact');
  perform pg_temp.assert_true((entire ->> 'calculated_total_cents')::int = 4000, 'entire show changed the legacy total');

  select value into scoped
  from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001',
    array['20000000-0000-0000-0000-000000000001']::uuid[]
  ) value;
  perform pg_temp.assert_true(scoped ->> 'payment_allocation_status' = 'exact', 'zero-payment partial scope was not exact');
  perform pg_temp.assert_true((scoped ->> 'entry_count')::int = 2, 'partial entry count crossed scope');
  perform pg_temp.assert_true((scoped ->> 'calculated_total_cents')::int = 2700, 'partial charge total is wrong');
  perform pg_temp.assert_true(jsonb_array_length(scoped -> 'section_breakdown') = 1, 'partial breakdown crossed scope');

  select value into duplicate_scope
  from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001',
    array['20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001']::uuid[]
  ) value;
  perform pg_temp.assert_true(duplicate_scope -> 'calculated_total_cents' = scoped -> 'calculated_total_cents', 'duplicate section changed totals');
end $$;

update public.legacy_balance_fixture
set value = value || '{"paid_online_cents":4000,"balance_due_cents":0,"payment_status":"paid"}'::jsonb;
do $$
declare scoped jsonb; entire jsonb;
begin
  select value into scoped from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001', array['20000000-0000-0000-0000-000000000001']::uuid[]) value;
  perform pg_temp.assert_true(scoped ->> 'payment_allocation_status' = 'ambiguous', 'whole-show payment was assigned to a partial scope');
  perform pg_temp.assert_true(scoped -> 'paid_online_cents' = 'null'::jsonb, 'ambiguous payment exposed a scoped amount');
  select value into entire from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001', array['20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002']::uuid[]) value;
  perform pg_temp.assert_true((entire ->> 'paid_online_cents')::int = 4000, 'entire show lost an unallocated payment');
end $$;

update public.legacy_balance_fixture
set value = value || '{"paid_online_cents":0,"discount_cents":500,"calculated_total_cents":3500,"balance_due_cents":3500}'::jsonb;
do $$
declare scoped jsonb;
begin
  select value into scoped from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001', array['20000000-0000-0000-0000-000000000001']::uuid[]) value;
  perform pg_temp.assert_true(scoped ->> 'payment_allocation_status' = 'ambiguous', 'whole-balance discount was allocated to a partial scope');
end $$;

do $$
begin
  begin
    perform public.report_show_exhibitor_balances_scoped('10000000-0000-0000-0000-000000000001', '{}'::uuid[]);
    raise exception 'empty scope accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.report_show_exhibitor_balances_scoped('10000000-0000-0000-0000-000000000001', array['20000000-0000-0000-0000-000000000003']::uuid[]);
    raise exception 'disabled scope accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.report_show_exhibitor_balances_scoped('10000000-0000-0000-0000-000000000001', array['90000000-0000-0000-0000-000000000001']::uuid[]);
    raise exception 'foreign scope accepted';
  exception when sqlstate '22023' then null; end;
end $$;

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"50000000-0000-0000-0000-000000000001"}', false);
do $$
begin
  begin
    perform public.report_show_exhibitor_balances_scoped('10000000-0000-0000-0000-000000000001', array['20000000-0000-0000-0000-000000000001']::uuid[]);
    raise exception 'unauthorized caller accepted';
  exception when insufficient_privilege then null; end;
end $$;

select 'closeout scoped financial balance contract passed' as result;
