-- Supabase default privileges grant new functions to anon/PUBLIC. Cursor
-- endpoints must keep the authenticated/service-only contract of the existing
-- roster and result-row RPCs; bounds must not broaden access to exhibitor data.
revoke all on function public.report_results_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer)
  from public, anon;
grant execute on function public.report_results_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer)
  to authenticated, service_role;
revoke all on function public.get_show_checkin_roster_page(uuid,text,text,uuid,integer)
  from public, anon;
grant execute on function public.get_show_checkin_roster_page(uuid,text,text,uuid,integer)
  to authenticated, service_role;
