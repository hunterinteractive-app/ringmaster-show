-- Separate, invite-only access for the Sweepstakes Portal. These records do
-- not grant a RingMaster Show role or any access to show administration.
create table if not exists public.sweepstakes_portal_clubs (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null,
  normalized_name text generated always as (lower(btrim(name))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (normalized_name)
);

create table if not exists public.sweepstakes_portal_assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  portal_club_id uuid not null references public.sweepstakes_portal_clubs(id) on delete cascade,
  recipient_email text not null,
  normalized_email text generated always as (lower(btrim(recipient_email))) stored,
  can_manage_points boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (portal_club_id, normalized_email)
);

create table if not exists public.sweepstakes_point_schedules (
  id uuid primary key default extensions.gen_random_uuid(),
  portal_club_id uuid not null references public.sweepstakes_portal_clubs(id) on delete cascade,
  effective_on date not null,
  rules jsonb not null default '{}'::jsonb,
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (portal_club_id, effective_on)
);

-- A platform tester may preview every club but cannot modify a chair's point
-- schedule unless separately assigned as that chair.
create table if not exists public.sweepstakes_portal_testers (
  id uuid primary key default extensions.gen_random_uuid(),
  email text not null,
  normalized_email text generated always as (lower(btrim(email))) stored,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (normalized_email)
);

create table if not exists public.sweepstakes_portal_legal_acceptances (
  user_id uuid primary key references auth.users(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  accepted_at timestamptz not null default now()
);

create index if not exists sweepstakes_portal_assignments_email_idx
  on public.sweepstakes_portal_assignments (normalized_email)
  where is_active;

create index if not exists sweepstakes_point_schedules_club_effective_idx
  on public.sweepstakes_point_schedules (portal_club_id, effective_on desc);

alter table public.sweepstakes_portal_clubs enable row level security;
alter table public.sweepstakes_portal_assignments enable row level security;
alter table public.sweepstakes_point_schedules enable row level security;
alter table public.sweepstakes_portal_testers enable row level security;
alter table public.sweepstakes_portal_legal_acceptances enable row level security;

-- Seed portal access from the same recipient addresses that receive each club's
-- reports today. This is an explicit migration of existing delivery settings,
-- not an email-based self-service claim.
insert into public.sweepstakes_portal_clubs (name)
select distinct btrim(sanction.club_name)
from public.show_sanctions sanction
where nullif(btrim(sanction.club_name), '') is not null
on conflict (normalized_name) do nothing;

insert into public.sweepstakes_portal_assignments (portal_club_id, recipient_email)
select distinct portal_club.id, btrim(sanction.sweepstakes_email)
from public.show_sanctions sanction
join public.sweepstakes_portal_clubs portal_club
  on portal_club.normalized_name = lower(btrim(sanction.club_name))
where nullif(btrim(sanction.sweepstakes_email), '') is not null
on conflict (portal_club_id, normalized_email) do nothing;

insert into public.sweepstakes_portal_testers (email)
values ('samuelzhunter94@gmail.com')
on conflict (normalized_email) do update set is_active = true;

-- Portal identity is deliberately derived only from explicit assignments.
-- A matching report-recipient email alone never opens up unassigned clubs.
create or replace function public.is_sweepstakes_portal_member(p_portal_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sweepstakes_portal_assignments assignment
    where assignment.portal_club_id = p_portal_club_id
      and assignment.is_active
      and assignment.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.can_manage_sweepstakes_points(p_portal_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sweepstakes_portal_assignments assignment
    where assignment.portal_club_id = p_portal_club_id
      and assignment.is_active
      and assignment.can_manage_points
      and assignment.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.is_sweepstakes_portal_tester()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sweepstakes_portal_testers tester
    where tester.is_active
      and tester.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

create or replace function public.can_preview_sweepstakes_portal_club(p_portal_club_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select (select public.is_sweepstakes_portal_tester())
      or (select public.is_sweepstakes_portal_member(p_portal_club_id));
$$;

create or replace function public.record_sweepstakes_portal_legal_acceptance(
  p_terms_version text,
  p_privacy_version text
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.sweepstakes_portal_legal_acceptances (
    user_id, terms_version, privacy_version, accepted_at
  ) values (
    (select auth.uid()), p_terms_version, p_privacy_version, now()
  )
  on conflict (user_id) do update
  set terms_version = excluded.terms_version,
      privacy_version = excluded.privacy_version,
      accepted_at = excluded.accepted_at;
$$;

grant select on public.sweepstakes_portal_clubs,
  public.sweepstakes_portal_assignments,
  public.sweepstakes_point_schedules,
  public.sweepstakes_portal_legal_acceptances to authenticated;
grant insert, update on public.sweepstakes_point_schedules to authenticated;
grant insert, update on public.sweepstakes_portal_legal_acceptances to authenticated;
revoke all on function public.is_sweepstakes_portal_member(uuid),
  public.can_manage_sweepstakes_points(uuid),
  public.is_sweepstakes_portal_tester(),
  public.can_preview_sweepstakes_portal_club(uuid) from public;
grant execute on function public.is_sweepstakes_portal_member(uuid),
  public.can_manage_sweepstakes_points(uuid),
  public.is_sweepstakes_portal_tester(),
  public.can_preview_sweepstakes_portal_club(uuid),
  public.record_sweepstakes_portal_legal_acceptance(text, text) to authenticated;

create policy "Portal members can read their sweepstakes clubs"
  on public.sweepstakes_portal_clubs
  for select to authenticated
  using ((select public.can_preview_sweepstakes_portal_club(id)));

create policy "Portal members can read their own club assignments"
  on public.sweepstakes_portal_assignments
  for select to authenticated
  using ((select public.is_sweepstakes_portal_member(portal_club_id)));

create policy "Portal members can read their point schedules"
  on public.sweepstakes_point_schedules
  for select to authenticated
  using ((select public.can_preview_sweepstakes_portal_club(portal_club_id)));

create policy "Portal users can read their own agreement"
  on public.sweepstakes_portal_legal_acceptances
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Portal users can record their own agreement"
  on public.sweepstakes_portal_legal_acceptances
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "Portal users can refresh their own agreement"
  on public.sweepstakes_portal_legal_acceptances
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "Point managers can add future schedules"
  on public.sweepstakes_point_schedules
  for insert to authenticated
  with check (
    (select public.can_manage_sweepstakes_points(portal_club_id))
    and created_by = (select auth.uid())
  );

create policy "Point managers can revise their schedules"
  on public.sweepstakes_point_schedules
  for update to authenticated
  using ((select public.can_manage_sweepstakes_points(portal_club_id)))
  with check (
    (select public.can_manage_sweepstakes_points(portal_club_id))
    and created_by = (select auth.uid())
  );

-- This is intentionally an RPC instead of a policy on Show tables. Portal
-- users receive a purpose-built summary and never direct table access to a
-- show's entries, exhibitors, financials, or administrative report records.
create or replace function public.list_sweepstakes_portal_shows()
returns table (
  portal_club_id uuid,
  club_name text,
  show_id uuid,
  show_name text,
  show_date date,
  show_location text,
  breed_name text,
  sanction_number text,
  sanctioning_body text,
  section_label text,
  eligible_entry_count integer,
  report_status text,
  report_artifact_id uuid
)
language sql
stable
security definer
set search_path = ''
as $$
  with assigned_clubs as (
    select distinct portal_club.id, portal_club.name, portal_club.normalized_name
    from public.sweepstakes_portal_clubs portal_club
    left join public.sweepstakes_portal_assignments assignment
      on assignment.portal_club_id = portal_club.id
     and assignment.is_active
     and assignment.normalized_email = lower(coalesce(auth.jwt() ->> 'email', ''))
    where (select public.is_sweepstakes_portal_tester())
       or assignment.id is not null
  )
  select
    portal_club.id,
    portal_club.name,
    sanction.show_id,
    show.name,
    show.start_date,
    show.location_name,
    sanction.breed_name,
    sanction.sanction_number,
    sanction.sanctioning_body,
    coalesce(nullif(section.display_name, ''), initcap(section.kind::text) || ' ' || upper(section.letter::text)),
    count(entry.id) filter (
      where entry.scratched_at is null
        and lower(coalesce(entry.status, '')) <> 'scratched'
        and (
          upper(btrim(sanction.sanctioning_body)) = 'STATE CLUB'
          or lower(btrim(coalesce(entry.breed, ''))) = lower(btrim(coalesce(sanction.breed_name, '')))
        )
    )::integer,
    case
      when bool_or(artifact.artifact_status = 'generated'::public.artifact_status) then 'generated'
      when bool_or(artifact.artifact_status = 'failed'::public.artifact_status) then 'failed'
      when bool_or(artifact.artifact_status = 'queued'::public.artifact_status) then 'queued'
      else 'not_ready'
    end,
    (array_agg(artifact.id) filter (where artifact.artifact_status = 'generated'))[1]
  from assigned_clubs portal_club
  join public.show_sanctions sanction
    on lower(btrim(coalesce(sanction.club_name, ''))) = portal_club.normalized_name
  join public.shows show on show.id = sanction.show_id
  left join public.show_sections section on section.id = sanction.section_id
  left join public.entries entry
    on entry.show_id = sanction.show_id
   and (sanction.section_id is null or entry.section_id = sanction.section_id)
  left join public.show_report_artifacts artifact
    on artifact.show_id = sanction.show_id
   and artifact.is_current
   and artifact.report_name = 'sweepstakes_report'::public.report_type
   and lower(btrim(coalesce(artifact.metadata ->> 'club_name', ''))) = portal_club.normalized_name
   and coalesce(artifact.metadata ->> 'sanction_number', '') = coalesce(sanction.sanction_number, '')
  group by
    portal_club.id, portal_club.name, sanction.show_id, show.name, show.start_date,
    show.location_name, sanction.breed_name, sanction.sanction_number,
    sanction.sanctioning_body, section.display_name, section.kind, section.letter;
$$;

revoke all on function public.list_sweepstakes_portal_shows() from public;
grant execute on function public.list_sweepstakes_portal_shows() to authenticated;
