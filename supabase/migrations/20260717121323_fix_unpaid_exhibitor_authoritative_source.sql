do $migration$
declare
  v_definition text;
  v_old text := E'    where b.show_id = p_show_id\n    order by b.id\n  loop\n';
  v_new text := E'    where b.show_id = p_show_id\n      and (\n        b.source = ''entries''\n        or not exists (\n          select 1\n          from public.show_exhibitor_balances authoritative\n          where authoritative.show_id = b.show_id\n            and authoritative.exhibitor_id = b.exhibitor_id\n            and authoritative.source = ''entries''\n        )\n      )\n    order by b.id\n  loop\n';
begin
  select pg_get_functiondef(
    'public.report_show_exhibitor_balances_scoped(uuid,uuid[])'::regprocedure
  ) into v_definition;

  if strpos(v_definition, v_old) = 0 then
    raise exception 'Unexpected scoped balance function definition';
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$migration$;

comment on function public.report_show_exhibitor_balances_scoped(uuid, uuid[])
is 'Read-only exact-section Closeout balances. Selects the authoritative entries-derived exhibitor snapshot and ignores superseded cart snapshots; legacy fallback applies only when no entries snapshot exists.';
