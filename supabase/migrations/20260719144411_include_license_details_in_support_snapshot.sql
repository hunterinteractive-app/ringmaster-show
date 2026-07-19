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
  v_license record;
  v_can_create boolean := false;
  v_remaining_show_days integer := 0;
  v_unlimited_active boolean := false;
  v_unlimited_expires_at timestamptz := null;
  v_license_message text := 'No license found.';
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
    select 1 from public.role_assignments ra
    where ra.user_id = p_target_user_id and ra.role = 'super_admin'
  ) into v_is_super_admin;

  select exists (
    select 1 from public.role_assignments ra
    where ra.user_id = p_target_user_id
      and ra.role in ('super_admin', 'admin', 'superintendent', 'reporting_clerk')
  ) into v_has_admin_role;

  select exists (
    select 1 from public.show_admins sa where sa.user_id = p_target_user_id
  ) into v_has_show_admin;

  select exists (
    select 1 from public.role_assignments ra where ra.user_id = p_target_user_id
  ) into v_has_any_assignment;

  select *
  into v_license
  from public.account_license_balances alb
  where alb.user_id = p_target_user_id;

  if found then
    v_unlimited_expires_at := v_license.unlimited_expires_at;

    if coalesce(v_license.unlimited_active, false)
       and v_license.unlimited_expires_at is not null
       and v_license.unlimited_expires_at > now() then
      v_can_create := true;
      v_remaining_show_days := 999999;
      v_unlimited_active := true;
      v_license_message := 'Unlimited active.';
    else
      v_remaining_show_days := greatest(
        coalesce(v_license.purchased_show_days, 0)
          - coalesce(v_license.consumed_show_days, 0),
        0
      );
      v_can_create := v_remaining_show_days > 0;
      v_license_message := case
        when v_can_create then 'Show days available.'
        else 'No show days remaining.'
      end;
    end if;
  end if;

  v_has_available_capacity := v_can_create;

  select coalesce(jsonb_agg(show_id order by show_id), '[]'::jsonb)
  into v_admin_show_ids
  from (
    select ra.show_id::text as show_id
    from public.role_assignments ra
    where ra.user_id = p_target_user_id
      and ra.show_id is not null
      and ra.role in ('super_admin', 'admin', 'superintendent', 'reporting_clerk')
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
    'admin_show_ids', v_admin_show_ids,
    'can_create', v_can_create,
    'remaining_show_days', v_remaining_show_days,
    'unlimited_active', v_unlimited_active,
    'unlimited_expires_at', v_unlimited_expires_at,
    'message', v_license_message
  );
end;
$function$;
