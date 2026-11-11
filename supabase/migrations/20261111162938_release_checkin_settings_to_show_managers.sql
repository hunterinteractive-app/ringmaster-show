-- Release check-in setup to the same owners, secretaries/admins and superadmins
-- who can manage other show settings. Existing RLS and token-generation guards
-- call this helper. No portal is enabled and no existing token is rotated.
create or replace function public.user_can_manage_show_checkin_settings(p_show_id uuid)
returns boolean
language sql stable security invoker
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and public.user_can_manage_show_settings(p_show_id, (select auth.uid()));
$$;
revoke all on function public.user_can_manage_show_checkin_settings(uuid) from public, anon;
grant execute on function public.user_can_manage_show_checkin_settings(uuid) to authenticated, service_role;
