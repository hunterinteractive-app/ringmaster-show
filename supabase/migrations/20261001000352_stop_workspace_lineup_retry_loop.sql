-- SQLSTATE 40001 is reserved for serialization failures. PostgREST 14 retries
-- those failures, so using it for an optimistic-concurrency conflict can trap a
-- request in an infinite retry loop. Preserve the HTTP 409 response without
-- marking the transaction as retryable.
do $$
declare
  v_target regprocedure;
  v_definition text;
  v_updated text;
begin
  foreach v_target in array array[
    'private.mutate_workspace_lineup(uuid,jsonb,text,jsonb)'::regprocedure,
    'private.mutate_workspace_lineup_core(uuid,jsonb,text,jsonb)'::regprocedure,
    'public.save_workspace_assignment(uuid,uuid,text,integer,text,timestamptz)'::regprocedure,
    'report_generation_private.add_checkin_fee_charge(uuid,uuid,uuid,text,integer,jsonb)'::regprocedure
  ] loop
    v_definition := pg_get_functiondef(v_target);
    v_updated := replace(
      v_definition,
      'errcode=''40001''',
      'errcode=''PT409'''
    );

    if v_updated = v_definition then
      if position('errcode=''PT409''' in v_definition) > 0 then
        continue;
      end if;
      raise exception 'Expected SQLSTATE 40001 or PT409 guard was not found in %', v_target;
    end if;

    execute v_updated;
  end loop;
end;
$$;
