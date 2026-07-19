set lock_timeout = '5s';

create or replace function public.support_user_access_snapshot(
  p_target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_show_ids jsonb;
  v_is_super_admin boolean;
  v_has_admin_role boolean;
  v_has_show_admin boolean;
  v_has_available_capacity boolean;
  v_has_any_assignment boolean;
begin
  if (select auth.uid()) is null or not public.is_super_admin() then
    raise exception 'Only super administrators can inspect support access.'
      using errcode = '42501';
  end if;

  if p_target_user_id is null then
    raise exception 'A target user is required.'
      using errcode = '22004';
  end if;

  select exists (
    select 1
    from public.role_assignments ra
    where ra.user_id = p_target_user_id
      and ra.role = 'super_admin'
  )
  into v_is_super_admin;

  select exists (
    select 1
    from public.role_assignments ra
    where ra.user_id = p_target_user_id
      and ra.role in (
        'super_admin',
        'admin',
        'superintendent',
        'reporting_clerk'
      )
  )
  into v_has_admin_role;

  select exists (
    select 1
    from public.show_admins sa
    where sa.user_id = p_target_user_id
  )
  into v_has_show_admin;

  select exists (
    select 1
    from public.role_assignments ra
    where ra.user_id = p_target_user_id
  )
  into v_has_any_assignment;

  select exists (
    select 1
    from public.account_license_balances alb
    where alb.user_id = p_target_user_id
      and (
        coalesce(alb.unlimited_access, false)
        or coalesce(alb.unlimited_active, false)
        or coalesce(alb.purchased_show_days, 0)
          > coalesce(alb.consumed_show_days, 0)
      )
  )
  into v_has_available_capacity;

  select coalesce(jsonb_agg(show_id order by show_id), '[]'::jsonb)
  into v_admin_show_ids
  from (
    select ra.show_id::text as show_id
    from public.role_assignments ra
    where ra.user_id = p_target_user_id
      and ra.show_id is not null
      and ra.role in (
        'super_admin',
        'admin',
        'superintendent',
        'reporting_clerk'
      )
    union
    select sa.show_id::text
    from public.show_admins sa
    where sa.user_id = p_target_user_id
  ) allowed_shows;

  return jsonb_build_object(
    'is_super_admin', v_is_super_admin,
    'can_access_admin',
      v_has_admin_role
      or v_has_show_admin
      or v_has_available_capacity
      or v_has_any_assignment,
    'has_available_show_capacity', v_has_available_capacity,
    'has_any_assigned_shows', v_has_any_assignment,
    'admin_show_ids', v_admin_show_ids
  );
end;
$function$;
