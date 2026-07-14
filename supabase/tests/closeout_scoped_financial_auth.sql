-- Authorization and scope-safety contracts for the production-shaped local
-- schema. Fixtures are deterministic and every change is rolled back.

begin;
select plan(1);

insert into public.shows (id, name, start_date, end_date)
values ('20000000-0000-0000-0000-000000000099', 'Foreign auth fixture',
        current_date, current_date)
on conflict (id) do nothing;

insert into public.show_sections (
  id, show_id, kind, letter, display_name, is_enabled, sort_order
) values
  ('21000000-0000-0000-0000-000000000098',
   '20000000-0000-0000-0000-000000000004',
   'open', 'Z', 'Disabled auth fixture', false, 980),
  ('21000000-0000-0000-0000-000000000099',
   '20000000-0000-0000-0000-000000000099',
   'open', 'Z', 'Foreign auth fixture', true, 990)
on conflict (id) do nothing;

insert into public.show_managers (
  show_id, user_id, can_manage_entries, can_manage_settings, can_finalize
) values (
  '20000000-0000-0000-0000-000000000004',
  '60000000-0000-0000-0000-000000000001',
  true, true, true
) on conflict (show_id, user_id) do update set
  can_manage_entries = true,
  can_manage_settings = true,
  can_finalize = true;

-- The anonymous role has no EXECUTE grant at all.
do $$
begin
  if has_function_privilege(
    'anon',
    'public.report_show_exhibitor_balances_scoped(uuid,uuid[])',
    'execute'
  ) then
    raise exception 'anonymous role retained scoped financial EXECUTE';
  end if;
end $$;

-- Authenticated non-managers reach the function but are rejected by its
-- owner/manager authorization guard.
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"60000000-0000-0000-0000-000000000002"}',
  true
);
set local role authenticated;
do $$
begin
  begin
    perform public.report_show_exhibitor_balances_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    );
    raise exception 'authenticated non-manager unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- An authorized show manager can execute the exact-scope projection.
select set_config(
  'request.jwt.claims',
  '{"role":"authenticated","sub":"60000000-0000-0000-0000-000000000001"}',
  true
);
set local role authenticated;
do $$
begin
  if not exists (
    select 1 from public.report_show_exhibitor_balances_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000004']::uuid[]
    )
  ) then
    raise exception 'authorized manager received no scoped balances';
  end if;
end $$;
reset role;

-- Service-role access bypasses manager membership, as required by the worker.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
do $$
begin
  perform public.report_show_exhibitor_balances_scoped(
    '20000000-0000-0000-0000-000000000004',
    array['21000000-0000-0000-0000-000000000004']::uuid[]
  );
end $$;
reset role;

-- Invalid scopes are rejected before any financial projection is returned.
do $$
begin
  begin
    perform public.report_show_exhibitor_balances_scoped(
      '20000000-0000-0000-0000-000000000004', '{}'::uuid[]
    );
    raise exception 'empty section array unexpectedly succeeded';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.report_show_exhibitor_balances_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000098']::uuid[]
    );
    raise exception 'disabled section unexpectedly succeeded';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform public.report_show_exhibitor_balances_scoped(
      '20000000-0000-0000-0000-000000000004',
      array['21000000-0000-0000-0000-000000000099']::uuid[]
    );
    raise exception 'foreign-show section unexpectedly succeeded';
  exception when sqlstate '22023' then null;
  end;
end $$;

-- Duplicate section IDs must not duplicate charges, and an all-enabled scope
-- must preserve every value returned by the legacy whole-show RPC.
do $$
declare
  v_single jsonb;
  v_duplicate jsonb;
  v_legacy jsonb;
  v_entire jsonb;
begin
  select value into v_single
  from public.report_show_exhibitor_balances_scoped(
    '20000000-0000-0000-0000-000000000004',
    array['21000000-0000-0000-0000-000000000004']::uuid[]
  ) value
  where value ->> 'exhibitor_id' = '30000000-0000-0000-0000-000000000001';

  select value into v_duplicate
  from public.report_show_exhibitor_balances_scoped(
    '20000000-0000-0000-0000-000000000004',
    array[
      '21000000-0000-0000-0000-000000000004',
      '21000000-0000-0000-0000-000000000004'
    ]::uuid[]
  ) value
  where value ->> 'exhibitor_id' = '30000000-0000-0000-0000-000000000001';

  if v_single -> 'calculated_total_cents'
     is distinct from v_duplicate -> 'calculated_total_cents' then
    raise exception 'duplicate section IDs changed scoped charges';
  end if;

  for v_legacy in
    select to_jsonb(value) from public.report_show_exhibitor_balances(
      '20000000-0000-0000-0000-000000000004'
    ) value
  loop
    select value into v_entire
    from public.report_show_exhibitor_balances_scoped(
      '20000000-0000-0000-0000-000000000004',
      array[
        '21000000-0000-0000-0000-000000000004',
        '21000000-0000-0000-0000-000000000005',
        '21000000-0000-0000-0000-000000000006',
        '21000000-0000-0000-0000-000000000007'
      ]::uuid[]
    ) value
    where value ->> 'balance_id' = v_legacy ->> 'balance_id';

    if (v_entire - 'scope_is_entire_show'
                 - 'payment_allocation_status'
                 - 'payment_allocation_ambiguity_reasons')
       is distinct from v_legacy then
      raise exception 'entire-show projection changed legacy balance %',
        v_legacy ->> 'balance_id';
    end if;
  end loop;
end $$;

select pass('scoped financial authorization and validation contracts');
rollback;
