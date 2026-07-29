-- The platform owner uses the tester login to validate every club's portal
-- before release. This explicit assignment grants point-schedule management
-- only; it does not grant Show or Club administrative roles.
insert into public.sweepstakes_portal_assignments (
  portal_club_id,
  recipient_email,
  can_manage_points,
  is_active
)
select
  club.id,
  'samuelzhunter94@gmail.com',
  true,
  true
from public.sweepstakes_portal_clubs club
on conflict (portal_club_id, normalized_email) do update
set can_manage_points = true,
    is_active = true,
    updated_at = now();
