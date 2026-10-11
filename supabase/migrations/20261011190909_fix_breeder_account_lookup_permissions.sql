-- Narrow server-only lookup; do not expose the auth table.
alter function public.breeder_verified_account(text) security definer;
alter function public.breeder_verified_account(text) set search_path = '';
revoke all on function public.breeder_verified_account(text) from public, anon, authenticated;
grant execute on function public.breeder_verified_account(text) to service_role;
