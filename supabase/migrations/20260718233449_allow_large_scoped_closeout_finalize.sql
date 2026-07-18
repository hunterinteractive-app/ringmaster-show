-- Large shows routinely need more than the authenticated role's default
-- statement timeout to atomically build their closeout snapshot and report
-- queue. Keep the exception scoped to this service-role-only RPC and below
-- PostgREST's maximum request duration.
alter function public.finalize_show_scoped(
  uuid,
  uuid[],
  text,
  text
) set statement_timeout = '55s';
-- Large shows routinely need more than the authenticated role's default
-- statement timeout to atomically build their closeout snapshot and report
-- queue. Keep the exception scoped to this service-role-only RPC and below
-- PostgREST's maximum request duration.
alter function public.finalize_show_scoped(
  uuid,
  uuid[],
  text,
  text
) set statement_timeout = '55s';
