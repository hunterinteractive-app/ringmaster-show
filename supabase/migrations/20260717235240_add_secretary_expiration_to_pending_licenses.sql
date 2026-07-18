set lock_timeout = '5s';

alter table public.pending_licenses
  add column if not exists secretary_license_expires_at timestamptz null;

comment on column public.pending_licenses.secretary_license_expires_at is
  'Secretary License expiration transferred to account_license_balances when the pending purchase is claimed. NULL means lifetime when can_change_host_club is true.';

create or replace function public.claim_pending_licenses(
  p_user_id uuid,
  p_email text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  rec record;
  v_claimed_count integer := 0;
begin
  for rec in
    select *
    from public.pending_licenses
    where lower(email) = lower(p_email)
      and claimed_at is null
  loop
    insert into public.account_license_balances (
      user_id,
      purchased_show_days,
      unlimited_access,
      unlimited_active,
      unlimited_expires_at,
      can_change_host_club,
      secretary_license_expires_at,
      updated_at
    )
    values (
      p_user_id,
      coalesce(rec.purchased_show_days, 0),
      coalesce(rec.unlimited_access, false),
      coalesce(rec.unlimited_access, false),
      rec.unlimited_expires_at,
      coalesce(rec.can_change_host_club, false),
      case
        when coalesce(rec.can_change_host_club, false)
          then rec.secretary_license_expires_at
        else null
      end,
      now()
    )
    on conflict (user_id) do update
    set
      purchased_show_days =
        coalesce(public.account_license_balances.purchased_show_days, 0)
        + coalesce(rec.purchased_show_days, 0),
      unlimited_access =
        coalesce(public.account_license_balances.unlimited_access, false)
        or coalesce(rec.unlimited_access, false),
      unlimited_active =
        coalesce(public.account_license_balances.unlimited_active, false)
        or coalesce(rec.unlimited_access, false),
      unlimited_expires_at =
        coalesce(
          rec.unlimited_expires_at,
          public.account_license_balances.unlimited_expires_at
        ),
      secretary_license_expires_at =
        case
          when public.account_license_balances.can_change_host_club
            and public.account_license_balances.secretary_license_expires_at is null
            then null
          when coalesce(rec.can_change_host_club, false)
            and rec.secretary_license_expires_at is null
            then null
          when public.account_license_balances.can_change_host_club
            and coalesce(rec.can_change_host_club, false)
            then greatest(
              public.account_license_balances.secretary_license_expires_at,
              rec.secretary_license_expires_at
            )
          when coalesce(rec.can_change_host_club, false)
            then rec.secretary_license_expires_at
          else public.account_license_balances.secretary_license_expires_at
        end,
      can_change_host_club =
        public.account_license_balances.can_change_host_club
        or coalesce(rec.can_change_host_club, false),
      updated_at = now();

    update public.pending_licenses
    set claimed_at = now()
    where id = rec.id;

    v_claimed_count := v_claimed_count + 1;
  end loop;

  return v_claimed_count;
end;
$function$;;
