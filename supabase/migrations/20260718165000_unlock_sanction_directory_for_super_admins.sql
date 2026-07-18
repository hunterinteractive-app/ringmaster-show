-- Unlock the in-progress sanction directory for super admins only.

grant select on table public.super_admins to authenticated;
grant select on table public.breed_club_sanction_links to authenticated;
grant insert on table public.breed_club_link_reports to authenticated;

drop policy if exists "Users can read their own super admin record"
  on public.super_admins;
create policy "Users can read their own super admin record"
  on public.super_admins
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Super admins can read active sanction links"
  on public.breed_club_sanction_links;
create policy "Super admins can read active sanction links"
  on public.breed_club_sanction_links
  for select
  to authenticated
  using (
    is_active = true
    and exists (
      select 1
      from public.super_admins
      where super_admins.user_id = auth.uid()
    )
  );

drop policy if exists "Super admins can report sanction links"
  on public.breed_club_link_reports;
create policy "Super admins can report sanction links"
  on public.breed_club_link_reports
  for insert
  to authenticated
  with check (
    reported_by_user_id = auth.uid()
    and status = 'open'
    and exists (
      select 1
      from public.super_admins
      where super_admins.user_id = auth.uid()
    )
  );
