-- Run after the portal regeneration migration. Changes are always rolled back.
begin;
do $test$ declare a public.show_report_artifacts%rowtype; first_result jsonb; second_result jsonb; after_generation int; begin
select * into strict a from public.show_report_artifacts where is_current and report_name='sweepstakes_report' and artifact_status='generated' and not exists(select 1 from public.show_task_queue q where q.report_artifact_id=show_report_artifacts.id and q.task_status in ('queued','running')) limit 1;
first_result:=public.request_portal_report_regeneration(a.show_id,a.finalize_run_id,a.scope_key,a.id);
second_result:=public.request_portal_report_regeneration(a.show_id,a.finalize_run_id,a.scope_key,a.id);
select generation into after_generation from public.show_report_artifacts where id=a.id;
if first_result->>'queued_count'<>'1' or second_result->>'already_pending'<>'true' or after_generation<>a.generation+1 then raise exception 'Duplicate request reset generation'; end if;
if has_function_privilege('authenticated','public.request_portal_report_regeneration(uuid,uuid,text,uuid)','EXECUTE') or has_function_privilege('anon','public.request_portal_report_regeneration(uuid,uuid,text,uuid)','EXECUTE') then raise exception 'Unauthorized RPC exposure'; end if;
end;$test$;
rollback;
