-- Signed-in exhibitors may use the shared link directory from a published
-- show. Link maintenance and report resolution remain super-admin-only.

drop policy if exists "Exhibitors can read active sanction links"
  on public.breed_club_sanction_links;
create policy "Exhibitors can read active sanction links"
  on public.breed_club_sanction_links
  for select
  to authenticated
  using (is_active = true);

drop policy if exists "Exhibitors can read open sanction link reports"
  on public.breed_club_link_reports;
create policy "Exhibitors can read open sanction link reports"
  on public.breed_club_link_reports
  for select
  to authenticated
  using (
    status = 'open'
    and reported_by_user_id = (select auth.uid())
    and show_id is not null
    and exists (
      select 1
      from public.shows published_show
      where published_show.id = breed_club_link_reports.show_id
        and published_show.is_published = true
    )
  );

drop policy if exists "Exhibitors can report published show sanction links"
  on public.breed_club_link_reports;
create policy "Exhibitors can report published show sanction links"
  on public.breed_club_link_reports
  for insert
  to authenticated
  with check (
    reported_by_user_id = (select auth.uid())
    and status = 'open'
    and show_id is not null
    and exists (
      select 1
      from public.shows published_show
      where published_show.id = breed_club_link_reports.show_id
        and published_show.is_published = true
    )
  );
