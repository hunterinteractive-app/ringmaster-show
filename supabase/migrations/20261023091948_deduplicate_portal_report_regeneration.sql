-- The Edge Function authorizes the chair and exact report scope first.
-- Serialize requests per artifact so concurrent Download clicks reuse queued work.
create or replace function public.request_portal_report_regeneration(
 p_show_id uuid, p_finalize_run_id uuid, p_scope_key text, p_artifact_id uuid
) returns jsonb language plpgsql security definer set search_path='' as $function$
declare a public.show_report_artifacts%rowtype;
begin
 select * into a from public.show_report_artifacts
 where id=p_artifact_id and show_id=p_show_id and finalize_run_id=p_finalize_run_id
   and is_current for update;
 if not found then raise exception 'Report not available'; end if;
 if exists (select 1 from public.show_task_queue q
   where q.report_artifact_id=a.id and q.task_type='render_report'
   and q.task_status in ('queued','running')) then
   return jsonb_build_object('artifact_id',a.id,'queued_count',0,'already_pending',true);
 end if;
 -- Legacy scope keys are normalized by the artifact update trigger. Use the
 -- locked row's current scope, not a caller's potentially pre-normalization key.
 return public.requeue_single_closeout_artifact(p_show_id,p_finalize_run_id,a.scope_key,p_artifact_id);
end;
$function$;
revoke all on function public.request_portal_report_regeneration(uuid,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.request_portal_report_regeneration(uuid,uuid,text,uuid) to service_role;
