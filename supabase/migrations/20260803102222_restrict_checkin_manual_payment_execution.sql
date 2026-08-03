-- Manual payments are a staff-only operation.  The function itself also
-- checks the caller's show-management permission, but removing the public
-- grant prevents anonymous clients from invoking it at all.
revoke all on function public.record_checkin_manual_payment(
  uuid,
  uuid,
  integer,
  text,
  text,
  text
) from public, anon;

grant execute on function public.record_checkin_manual_payment(
  uuid,
  uuid,
  integer,
  text,
  text,
  text
) to authenticated, service_role;
