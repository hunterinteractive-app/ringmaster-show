-- Keep the database authorization sources aligned with the Flutter access
-- check: super admins may be recorded in either the legacy super_admins table
-- or the current role_assignments table.

drop policy if exists "Super admins can read active sanction links"
  on public.breed_club_sanction_links;
create policy "Super admins can read active sanction links"
  on public.breed_club_sanction_links
  for select
  to authenticated
  using (
    is_active = true
    and (
      exists (
        select 1
        from public.super_admins
        where super_admins.user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.role_assignments
        where role_assignments.user_id = (select auth.uid())
          and role_assignments.role = 'super_admin'
      )
    )
  );

drop policy if exists "Super admins can report sanction links"
  on public.breed_club_link_reports;
create policy "Super admins can report sanction links"
  on public.breed_club_link_reports
  for insert
  to authenticated
  with check (
    reported_by_user_id = (select auth.uid())
    and status = 'open'
    and (
      exists (
        select 1
        from public.super_admins
        where super_admins.user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.role_assignments
        where role_assignments.user_id = (select auth.uid())
          and role_assignments.role = 'super_admin'
      )
    )
  );
