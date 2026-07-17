\set ON_ERROR_STOP on

select set_config('request.jwt.claims', '{"role":"service_role"}', false);

begin;
set transaction read only;

do $$
declare
  scoped jsonb;
  row_count integer;
begin
  select value into scoped
  from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001',
    array['20000000-0000-0000-0000-000000000001']::uuid[]
  ) value;

  select count(*) into row_count
  from public.report_show_exhibitor_balances_scoped(
    '10000000-0000-0000-0000-000000000001',
    array['20000000-0000-0000-0000-000000000001']::uuid[]
  );

  if row_count <> 1 then
    raise exception 'cart snapshot was not superseded: % rows', row_count;
  end if;

  if scoped is null then
    raise exception 'read-only balance scope returned no report row';
  end if;
  if scoped ->> 'payment_allocation_status' <> 'exact' then
    raise exception 'unexpected allocation status: %',
      scoped ->> 'payment_allocation_status';
  end if;
  if (scoped ->> 'balance_due_cents')::integer <> 3400 then
    raise exception 'unexpected scoped balance: %',
      scoped ->> 'balance_due_cents';
  end if;
end $$;

rollback;

select 'read-only Closeout balance renderer RPC passed' as result;
