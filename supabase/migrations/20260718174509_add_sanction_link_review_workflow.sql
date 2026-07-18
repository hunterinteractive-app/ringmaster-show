alter table public.breed_club_link_reports
  add column if not exists proposed_url text;

grant select, update on table public.breed_club_link_reports to authenticated;
grant update on table public.breed_club_sanction_links to authenticated;

drop policy if exists "Super admins can review sanction link reports"
  on public.breed_club_link_reports;
create policy "Super admins can review sanction link reports"
  on public.breed_club_link_reports
  for select
  to authenticated
  using (
    exists (
      select 1 from public.super_admins
      where super_admins.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.role_assignments
      where role_assignments.user_id = (select auth.uid())
        and role_assignments.role = 'super_admin'
    )
  );

drop policy if exists "Super admins can resolve sanction link reports"
  on public.breed_club_link_reports;
create policy "Super admins can resolve sanction link reports"
  on public.breed_club_link_reports
  for update
  to authenticated
  using (
    exists (
      select 1 from public.super_admins
      where super_admins.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.role_assignments
      where role_assignments.user_id = (select auth.uid())
        and role_assignments.role = 'super_admin'
    )
  )
  with check (
    status in ('open', 'approved', 'dismissed')
    and (
      exists (
        select 1 from public.super_admins
        where super_admins.user_id = (select auth.uid())
      )
      or exists (
        select 1 from public.role_assignments
        where role_assignments.user_id = (select auth.uid())
          and role_assignments.role = 'super_admin'
      )
    )
  );

drop policy if exists "Super admins can update active sanction links"
  on public.breed_club_sanction_links;
create policy "Super admins can update active sanction links"
  on public.breed_club_sanction_links
  for update
  to authenticated
  using (
    is_active = true
    and (
      exists (
        select 1 from public.super_admins
        where super_admins.user_id = (select auth.uid())
      )
      or exists (
        select 1 from public.role_assignments
        where role_assignments.user_id = (select auth.uid())
          and role_assignments.role = 'super_admin'
      )
    )
  )
  with check (
    is_active = true
    and (
      exists (
        select 1 from public.super_admins
        where super_admins.user_id = (select auth.uid())
      )
      or exists (
        select 1 from public.role_assignments
        where role_assignments.user_id = (select auth.uid())
          and role_assignments.role = 'super_admin'
      )
    )
  );
