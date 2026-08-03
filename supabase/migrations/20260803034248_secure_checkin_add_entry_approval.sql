revoke all on function public.review_checkin_change_request(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.review_checkin_change_request(uuid, boolean, text)
  to authenticated, service_role;
