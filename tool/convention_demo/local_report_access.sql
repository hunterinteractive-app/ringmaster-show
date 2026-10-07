-- Sandbox-only operational-report access, scoped to the fictional show and
-- its existing staff authorization helper. Never apply to a hosted project.
drop policy if exists convention_operational_insert on public.show_report_artifacts;
create policy convention_operational_insert on public.show_report_artifacts for insert to authenticated
with check (public.user_can_finalize_show(show_id,auth.uid()) and scope_key='operational');
drop policy if exists convention_operational_update on public.show_report_artifacts;
create policy convention_operational_update on public.show_report_artifacts for update to authenticated
using (public.user_can_finalize_show(show_id,auth.uid()) and scope_key='operational')
with check (public.user_can_finalize_show(show_id,auth.uid()) and scope_key='operational');

drop policy if exists convention_report_storage on storage.objects;
create policy convention_report_storage on storage.objects for all to authenticated
using(bucket_id='show-files' and name like 'shows/ringmaster_convention_showcase/%' and public.user_can_finalize_show('95000000-0000-0000-0000-000000000001',auth.uid()))
with check(bucket_id='show-files' and name like 'shows/ringmaster_convention_showcase/%' and public.user_can_finalize_show('95000000-0000-0000-0000-000000000001',auth.uid()));
