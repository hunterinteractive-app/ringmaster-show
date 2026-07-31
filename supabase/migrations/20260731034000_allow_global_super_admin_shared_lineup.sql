-- A super-admin can open every superintendent show.  The shared line-up
-- readers and writer must use the same global super-admin rule, otherwise a
-- valid show opens with empty judges, entries, and assignments.

create or replace function public.user_can_view_show_lineup(p_show_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.role_assignments ra
    where ra.show_id = p_show_id
      and ra.user_id = auth.uid()
      and ra.role in ('admin', 'superintendent', 'reporting_clerk')
  )
  or exists (
    select 1
    from public.role_assignments ra
    where ra.user_id = auth.uid()
      and ra.role = 'super_admin'
  )
  or exists (
    select 1
    from public.super_admins sa
    where sa.user_id = auth.uid()
  );
$function$;

create or replace function public.user_can_manage_show_lineup(p_show_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $function$
  select exists (
    select 1
    from public.role_assignments ra
    where ra.show_id = p_show_id
      and ra.user_id = auth.uid()
      and ra.role in ('admin', 'superintendent')
  )
  or exists (
    select 1
    from public.role_assignments ra
    where ra.user_id = auth.uid()
      and ra.role = 'super_admin'
  )
  or exists (
    select 1
    from public.super_admins sa
    where sa.user_id = auth.uid()
  );
$function$;

revoke all on function public.user_can_view_show_lineup(uuid) from public, anon;
grant execute on function public.user_can_view_show_lineup(uuid) to authenticated, service_role;

revoke all on function public.user_can_manage_show_lineup(uuid) from public, anon;
grant execute on function public.user_can_manage_show_lineup(uuid) to authenticated, service_role;
