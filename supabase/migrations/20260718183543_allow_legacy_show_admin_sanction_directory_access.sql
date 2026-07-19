-- Show secretaries/admins may browse the shared directory and submit broken
-- link reports from a show they manage. Approval and link editing remain
-- protected by the existing super-admin-only update policies.

grant select on table public.breed_club_sanction_links to authenticated;
grant select, insert on table public.breed_club_link_reports to authenticated;

drop policy if exists "Show admins can read active sanction links"
  on public.breed_club_sanction_links;
create policy "Show admins can read active sanction links"
  on public.breed_club_sanction_links
  for select
  to authenticated
  using (
    is_active = true
    and exists (
      select 1
      from public.role_assignments assignment
      where assignment.user_id = (select auth.uid())
        and assignment.role = 'admin'::public.app_role
    )
    or (
      is_active = true
      and exists (
        select 1
        from public.show_admins legacy_assignment
        where legacy_assignment.user_id = (select auth.uid())
      )
    )
  );

drop policy if exists "Show admins can read open sanction link reports"
  on public.breed_club_link_reports;
create policy "Show admins can read open sanction link reports"
  on public.breed_club_link_reports
  for select
  to authenticated
  using (
    status = 'open'
    and exists (
      select 1
      from public.role_assignments assignment
      where assignment.user_id = (select auth.uid())
        and assignment.role = 'admin'::public.app_role
    )
    or (
      status = 'open'
      and exists (
        select 1
        from public.show_admins legacy_assignment
        where legacy_assignment.user_id = (select auth.uid())
      )
    )
  );

drop policy if exists "Show admins can report sanction links"
  on public.breed_club_link_reports;
create policy "Show admins can report sanction links"
  on public.breed_club_link_reports
  for insert
  to authenticated
  with check (
    reported_by_user_id = (select auth.uid())
    and status = 'open'
    and show_id is not null
    and exists (
      select 1
      from public.role_assignments assignment
      where assignment.user_id = (select auth.uid())
        and assignment.show_id = breed_club_link_reports.show_id
        and assignment.role = 'admin'::public.app_role
    )
    or (
      reported_by_user_id = (select auth.uid())
      and status = 'open'
      and show_id is not null
      and exists (
        select 1
        from public.show_admins legacy_assignment
        where legacy_assignment.user_id = (select auth.uid())
          and legacy_assignment.show_id = breed_club_link_reports.show_id
      )
    )
  );
