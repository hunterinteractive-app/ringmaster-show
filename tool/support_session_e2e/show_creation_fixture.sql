CREATE OR REPLACE FUNCTION public.create_show_with_license(p_name text, p_start_date date, p_end_date date, p_location_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid;
  v_show_id uuid;
  v_balance record;
  v_show_days integer;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Not signed in';
  end if;

  if p_end_date < p_start_date then
    raise exception 'End date cannot be before start date';
  end if;

  v_show_days := (p_end_date - p_start_date) + 1;

  select *
  into v_balance
  from public.account_license_balances
  where user_id = v_user_id
  for update;

  if not found then
    raise exception 'No license balance found';
  end if;

  if v_balance.unlimited_active = true
     and v_balance.unlimited_expires_at > now() then
    null;
  else
    if (
      coalesce(v_balance.purchased_show_days, 0)
      - coalesce(v_balance.consumed_show_days, 0)
    ) < v_show_days then
      raise exception 'Not enough licensed show days';
    end if;

    update public.account_license_balances
    set consumed_show_days = coalesce(consumed_show_days, 0) + v_show_days,
        updated_at = now()
    where user_id = v_user_id;
  end if;

  insert into public.shows (
    created_by,
    owner_user_id,
    name,
    start_date,
    end_date,
    location_name,
    timezone,
    is_published
  )
  values (
    v_user_id,
    v_user_id,
    p_name,
    p_start_date,
    p_end_date,
    p_location_name,
    'America/Indiana/Indianapolis',
    false
  )
  returning id into v_show_id;

  insert into public.role_assignments (
    show_id,
    user_id,
    role
  )
  values (
    v_show_id,
    v_user_id,
    'admin'
  )
  on conflict do nothing;

  return v_show_id;
end;
$function$
