-- Household membership does not grant roles, licenses, or show administration.
create schema if not exists household_private;
revoke all on schema household_private from public, anon, authenticated;
grant usage on schema household_private to authenticated, service_role;
create table household_private.invitations (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  email text not null check (email = lower(btrim(email)) and position('@' in email) > 1),
  member_user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  accepted_at timestamptz,
  revoked_at timestamptz,
  check (member_user_id is distinct from owner_user_id)
);
alter table household_private.invitations enable row level security;
revoke all on household_private.invitations from public, anon, authenticated;
create unique index household_invitation_active_email on household_private.invitations(owner_user_id,email) where revoked_at is null;
create index household_invitation_inbox on household_private.invitations(email) where revoked_at is null and accepted_at is null;
create index household_invitation_member on household_private.invitations(member_user_id,owner_user_id) where revoked_at is null;

create function household_private.can_invite_email(p_owner uuid,p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.exhibitors e where e.owner_user_id=p_owner
  and lower(btrim(e.email))=lower(btrim(p_email)) and e.is_active=true
  and (lower(e.type::text)='adult' or (lower(e.type::text)='youth'
    and e.birth_date is not null and e.birth_date <= (current_date - interval '14 years')::date)));
$$;
revoke all on function household_private.can_invite_email(uuid,text) from public,anon,authenticated;

create function household_private.has_access(p_owner uuid, p_actor uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = '' as $$
 select p_actor is not null and (p_owner = p_actor or exists (
   select 1 from household_private.invitations i
   where i.owner_user_id = p_owner and i.member_user_id = p_actor
     and i.accepted_at is not null and i.revoked_at is null
 ));
$$;
revoke all on function household_private.has_access(uuid,uuid) from public, anon;
grant execute on function household_private.has_access(uuid,uuid) to authenticated, service_role;

-- This RPC always checks the caller's identity, never a client-supplied actor.
create function public.can_access_household(p_owner_user_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $$
 select household_private.has_access(p_owner_user_id, auth.uid());
$$;
revoke all on function public.can_access_household(uuid) from public, anon;
grant execute on function public.can_access_household(uuid) to authenticated;

create function household_private.household_access(p_action text default 'list', p_invitation_id uuid default null, p_email text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 v_actor uuid := auth.uid(); v_email text; v_i household_private.invitations; v_result jsonb;
begin
 if v_actor is null then raise exception 'Sign in to manage household access.'; end if;
 select lower(btrim(email)) into v_email from auth.users where id=v_actor and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verify your email before managing household access.'; end if;
 if p_action = 'invite' then
   p_email := lower(btrim(p_email));
   if p_email is null or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(p_email)>254 then
     raise exception 'Enter a valid email address.';
   end if;
   if p_email=v_email then raise exception 'You already have access to your household.'; end if;
   if not household_private.can_invite_email(v_actor,p_email) then
     raise exception 'Use the email of an active adult exhibitor or a youth aged 14 or older with a birth date.';
   end if;
   -- Only the actual owner can invite into their own household. No transitive sharing.
   update household_private.invitations set revoked_at=now()
    where owner_user_id=v_actor and email=p_email and revoked_at is null and accepted_at is null and expires_at<=now();
   insert into household_private.invitations(owner_user_id,email) values(v_actor,p_email)
    on conflict (owner_user_id,email) where revoked_at is null do nothing;
 elsif p_action in ('accept','revoke','decline') then
   select * into v_i from household_private.invitations where id=p_invitation_id for update;
   if not found then raise exception 'Invitation is unavailable.'; end if;
   if p_action='accept' then
     if not household_private.can_invite_email(v_i.owner_user_id,v_i.email) or v_i.email<>v_email or v_i.revoked_at is not null or v_i.expires_at<=now() or v_i.owner_user_id=v_actor
        or (v_i.member_user_id is not null and v_i.member_user_id<>v_actor) then
       raise exception 'Invitation is unavailable for this login.';
     end if;
     update household_private.invitations set member_user_id=v_actor, accepted_at=now() where id=v_i.id;
   else
     if v_i.owner_user_id<>v_actor and v_i.member_user_id is distinct from v_actor
        and not(v_i.member_user_id is null and v_i.email=v_email) then
       raise exception 'You cannot change this invitation.';
     end if;
     update household_private.invitations set revoked_at=now() where id=v_i.id;
   end if;
 elsif p_action<>'list' then raise exception 'Unknown household action.';
 end if;
 select jsonb_build_object(
   'households', (select coalesce(jsonb_agg(h),'[]'::jsonb) from (
     select v_actor owner_user_id, 'My household'::text label, true is_owner
     union all
     select distinct i.owner_user_id, coalesce(u.email,'Shared household'), false
     from household_private.invitations i join auth.users u on u.id=i.owner_user_id
     where i.member_user_id=v_actor and i.accepted_at is not null and i.revoked_at is null
   ) h),
   'invitations', (select coalesce(jsonb_agg(x order by x.created_at),'[]'::jsonb) from (
     select i.id,i.owner_user_id,i.email,i.accepted_at,i.expires_at,i.created_at,
       u.email owner_email, (i.owner_user_id=v_actor) is_owner
     from household_private.invitations i join auth.users u on u.id=i.owner_user_id
     where i.revoked_at is null and (i.accepted_at is not null or i.expires_at>now())
       and (i.owner_user_id=v_actor or i.member_user_id=v_actor or (i.member_user_id is null and i.email=v_email))
   ) x)
 ) into v_result;
 return v_result;
end;
$$;
revoke all on function household_private.household_access(text,uuid,text) from public, anon;
grant execute on function household_private.household_access(text,uuid,text) to authenticated;
create function public.household_access(p_action text default 'list', p_invitation_id uuid default null, p_email text default null)
returns jsonb language sql security invoker set search_path = '' as $$
 select household_private.household_access(p_action,p_invitation_id,p_email);
$$;
revoke all on function public.household_access(text,uuid,text) from public, anon;
grant execute on function public.household_access(text,uuid,text) to authenticated;

create policy household_animals on public.animals for all to authenticated
 using (household_private.has_access(owner_user_id)) with check (household_private.has_access(owner_user_id));
create policy household_exhibitors_read on public.exhibitors for select to authenticated
 using (household_private.has_access(owner_user_id));
create policy household_exhibitors_insert on public.exhibitors for insert to authenticated
 with check (household_private.has_access(owner_user_id));
create policy household_exhibitors_update on public.exhibitors for update to authenticated
 using (household_private.has_access(owner_user_id)) with check (household_private.has_access(owner_user_id));
create policy household_entries_read on public.entries for select to authenticated
 using (household_private.has_access(exhibitor_user_id));
create policy household_entries_update on public.entries for update to authenticated
 using (household_private.has_access(exhibitor_user_id)) with check (household_private.has_access(exhibitor_user_id));
create policy household_carts on public.entry_carts for all to authenticated
 using (household_private.has_access(user_id)) with check (household_private.has_access(user_id));
create policy household_cart_items on public.entry_cart_items for all to authenticated
 using (exists(select 1 from public.entry_carts c where c.id=cart_id and household_private.has_access(c.user_id)))
 with check (exists(select 1 from public.entry_carts c where c.id=cart_id and household_private.has_access(c.user_id)));

-- Preserve existing deadlines, payment guards, staff checks, and entry validation.
-- Abort deployment if the expected authorization clauses have changed.
do $$
declare v_name text; v_def text; v_old text; v_new text;
begin
 foreach v_name in array array['calculate_entry_cart_balance','commit_entry_cart_day_of','set_entry_scratch_state','create_payment_quote_attempt'] loop
   select pg_get_functiondef(p.oid) into strict v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=v_name;
   if v_name='create_payment_quote_attempt' then
     v_old := 'v_cart.user_id is distinct from p_user_id';
     v_new := 'not household_private.has_access(v_cart.user_id, p_user_id)';
   elsif v_name='set_entry_scratch_state' then
     v_old := 'auth.uid() is distinct from v_entry.exhibitor_user_id';
     v_new := 'not household_private.has_access(v_entry.exhibitor_user_id)';
   else
     v_old := 'auth.uid() is distinct from v_cart.user_id';
     v_new := 'not household_private.has_access(v_cart.user_id)';
   end if;
   if position(v_old in v_def)=0 then raise exception 'Household migration: unexpected authorization in %',v_name; end if;
   execute replace(v_def,v_old,v_new);
 end loop;
end $$;

-- Household-scoped report readers retain the existing report eligibility rules.
CREATE OR REPLACE FUNCTION public.household_exhibitor_past_show_reports(p_owner_user_id uuid)
 RETURNS TABLE(artifact_id uuid, show_id uuid, show_name text, show_start_date date, show_end_date date, show_location text, report_name text, report_label text, exhibitor_id uuid, exhibitor_name text, file_name text, storage_bucket text, storage_path text, generated_at timestamp with time zone, legs_count integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select distinct on (a.id)
    a.id as artifact_id,
    s.id as show_id,
    s.name::text as show_name,
    s.start_date as show_start_date,
    s.end_date as show_end_date,
    coalesce(s.location_name, '')::text as show_location,
    a.report_name::text as report_name,
    case
      when a.report_name::text = 'exhibitor_report' then 'Exhibitor Report'
      when a.report_name::text = 'legs' then 'ARBA Legs'
      else initcap(replace(a.report_name::text, '_', ' '))
    end as report_label,
    (a.metadata->>'exhibitor_id')::uuid as exhibitor_id,
    coalesce(a.metadata->>'exhibitor_name', '')::text as exhibitor_name,
    coalesce(a.file_name, '')::text as file_name,
    a.storage_bucket,
    a.storage_path,
    a.generated_at,
    nullif(a.metadata->>'legs_count', '')::integer as legs_count
  from public.show_report_artifacts a
  join public.shows s
    on s.id = a.show_id
  left join public.exhibitors ex
    on ex.id::text = a.metadata->>'exhibitor_id'
  where household_private.has_access(p_owner_user_id) and a.report_name::text in ('exhibitor_report', 'legs')
    and a.artifact_status::text = 'generated'
    and a.is_current = true
    and a.storage_bucket is not null
    and a.storage_path is not null
    and a.metadata ? 'exhibitor_id'
    and (
      exists (
        select 1
        from public.entries e
        where e.show_id = a.show_id
          and e.exhibitor_id::text = a.metadata->>'exhibitor_id'
          and e.exhibitor_user_id = p_owner_user_id
      )
      or ex.owner_user_id = p_owner_user_id
      or ex.claimed_by_user_id = p_owner_user_id
    )
  order by
    a.id,
    a.generated_at desc nulls last;
$function$;
revoke all on function public.household_exhibitor_past_show_reports(uuid) from public, anon;
grant execute on function public.household_exhibitor_past_show_reports(uuid) to authenticated;
CREATE OR REPLACE FUNCTION public.household_exhibitor_report_download_info(p_artifact_id uuid, p_owner_user_id uuid)
 RETURNS TABLE(storage_bucket text, storage_path text, file_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    a.storage_bucket,
    a.storage_path,
    coalesce(a.file_name, 'report.pdf')::text as file_name
  from public.show_report_artifacts a
  left join public.exhibitors ex
    on ex.id::text = a.metadata->>'exhibitor_id'
  where household_private.has_access(p_owner_user_id) and a.id = p_artifact_id
    and a.report_name::text in ('exhibitor_report', 'legs')
    and a.artifact_status::text = 'generated'
    and a.is_current = true
    and a.storage_bucket is not null
    and a.storage_path is not null
    and a.metadata ? 'exhibitor_id'
    and (
      exists (
        select 1
        from public.entries e
        where e.show_id = a.show_id
          and e.exhibitor_id::text = a.metadata->>'exhibitor_id'
          and e.exhibitor_user_id = p_owner_user_id
      )
      or ex.owner_user_id = p_owner_user_id
      or ex.claimed_by_user_id = p_owner_user_id
    );
$function$;
revoke all on function public.household_exhibitor_report_download_info(uuid,uuid) from public, anon;
grant execute on function public.household_exhibitor_report_download_info(uuid,uuid) to authenticated;

do $$
declare v_def text;
begin
 -- Older deployments do not expose this optional confirmation RPC.
 if to_regprocedure('public.get_stripe_registration_status(text,uuid)') is null then return; end if;
 select pg_get_functiondef('public.get_stripe_registration_status(text,uuid)'::regprocedure) into v_def;
 if position('cart.user_id=auth.uid()' in v_def)=0 then raise exception 'Unexpected Stripe status authorization'; end if;
 execute replace(v_def,'cart.user_id=auth.uid()', 'household_private.has_access(cart.user_id)');
end $$;

-- The actor argument is supplied only by verified server endpoints.
revoke all on function public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer) from public, anon, authenticated;
grant execute on function public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer) to service_role;

-- Durable email bookkeeping; service endpoints reserve delivery and use the
-- invitation ID as the provider idempotency key. No mail is sent by migration.
alter table household_private.invitations add column email_sent_at timestamptz,
 add column email_first_attempt_at timestamptz, add column email_lease_until timestamptz,
 add column email_inviter text;
create function public.prepare_household_invitation_email(p_id uuid,p_owner uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i household_private.invitations; v_email text;
begin
 select * into i from household_private.invitations where id=p_id and owner_user_id=p_owner for update;
 if not found or i.revoked_at is not null or i.expires_at<=now() then raise exception 'Invitation unavailable.'; end if;
 if i.email_sent_at is not null or i.accepted_at is not null then return jsonb_build_object('send',false); end if;
 if not household_private.can_invite_email(p_owner,i.email) then raise exception 'Exhibitor is not eligible for a login invitation.'; end if;
 if i.email_first_attempt_at < now()-interval '23 hours' then raise exception 'Email delivery could not be confirmed. Revoke this invitation before creating another.'; end if;
 if i.email_lease_until>now() then raise exception 'Invitation email is already being sent. Please try again shortly.'; end if;
 select email into v_email from auth.users where id=p_owner and email_confirmed_at is not null;
 if v_email is null then raise exception 'Verified owner login required.'; end if;
 update household_private.invitations set email_first_attempt_at=coalesce(email_first_attempt_at,now()),
  email_lease_until=now()+interval '1 minute',email_inviter=coalesce(email_inviter,v_email) where id=p_id;
 return jsonb_build_object('send',true,'to',i.email,'inviter',coalesce(i.email_inviter,v_email));
end $$;
create function public.finish_household_invitation_email(p_id uuid,p_owner uuid) returns void
language sql security definer set search_path = '' as $$
 update household_private.invitations set email_sent_at=now(),email_lease_until=null
 where id=p_id and owner_user_id=p_owner and email_first_attempt_at is not null;
$$;
revoke all on function public.prepare_household_invitation_email(uuid,uuid), public.finish_household_invitation_email(uuid,uuid) from public,anon,authenticated;
grant execute on function public.prepare_household_invitation_email(uuid,uuid), public.finish_household_invitation_email(uuid,uuid) to service_role;

-- Read-only support snapshot. This does not impersonate the target login.
create function public.support_household_access(p_target_user_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := p_target_user_id; v_email text; v_result jsonb;
begin
 if auth.uid() is null or not public.is_super_admin() then
  raise exception 'Only super administrators can inspect support access.' using errcode='42501';
 end if;
 if v_actor is null then raise exception 'A target user is required.'; end if;
 select lower(btrim(email)) into v_email from auth.users where id=v_actor;
 select jsonb_build_object(
   'households', (select coalesce(jsonb_agg(h),'[]'::jsonb) from (
     select v_actor owner_user_id, 'My household'::text label, true is_owner
     union all
     select distinct i.owner_user_id, coalesce(u.email,'Shared household'), false
     from household_private.invitations i join auth.users u on u.id=i.owner_user_id
     where i.member_user_id=v_actor and i.accepted_at is not null and i.revoked_at is null
   ) h),
   'invitations', (select coalesce(jsonb_agg(x order by x.created_at),'[]'::jsonb) from (
     select i.id,i.owner_user_id,i.email,i.accepted_at,i.expires_at,i.created_at,
       u.email owner_email, (i.owner_user_id=v_actor) is_owner
     from household_private.invitations i join auth.users u on u.id=i.owner_user_id
     where i.revoked_at is null and (i.accepted_at is not null or i.expires_at>now())
       and (i.owner_user_id=v_actor or i.member_user_id=v_actor or (i.member_user_id is null and i.email=v_email))
   ) x)
 ) into v_result;

 return v_result;
end $$;
revoke all on function public.support_household_access(uuid) from public,anon;
grant execute on function public.support_household_access(uuid) to authenticated;
