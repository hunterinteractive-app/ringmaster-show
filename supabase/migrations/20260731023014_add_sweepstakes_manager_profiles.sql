-- A manager profile changes only the portal presentation. Club access remains
-- governed by sweepstakes_portal_assignments for the signed-in email.
create table if not exists public.sweepstakes_portal_manager_profiles (
  normalized_email text primary key,
  display_name text not null check (length(btrim(display_name)) > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.sweepstakes_portal_manager_profiles enable row level security;

create or replace function public.get_sweepstakes_portal_manager_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when auth.uid() is null then null
    else (
      select jsonb_build_object('display_name', profile.display_name)
      from public.sweepstakes_portal_manager_profiles profile
      where profile.is_active
        and profile.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  end;
$function$;

revoke all on table public.sweepstakes_portal_manager_profiles from anon, authenticated;
revoke execute on function public.get_sweepstakes_portal_manager_profile() from public;
grant execute on function public.get_sweepstakes_portal_manager_profile() to authenticated;
revoke execute on function public.get_sweepstakes_portal_manager_profile() from anon;
