-- Scope repair enqueues its repaired artifacts, and the following requeue
-- update counts those same task rows. Report the distinct work represented by
-- the final requeue/insert operations instead of adding the repair count twice.
do $block$
declare
  v_definition text;
  v_old text := '''queued_count'', v_requeued + v_inserted +' || chr(10) ||
    '      coalesce((v_repair ->> ''queued_count'')::integer, 0)';
  v_new text := '''queued_count'', v_requeued + v_inserted';
begin
  select pg_get_functiondef(p.oid)
    into v_definition
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'requeue_closeout_render_tasks'
    and p.proargtypes = '2950 2950 25 16'::pg_catalog.oidvector;

  if v_definition is null then
    raise exception 'public.requeue_closeout_render_tasks is required';
  end if;
  if strpos(v_definition, v_old) = 0 then
    raise exception 'Legacy queued-count expression was not found';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$block$;
