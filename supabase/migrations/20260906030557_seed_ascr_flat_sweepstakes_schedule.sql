-- The American Standard Chinchilla Rabbit Association scores each eligible
-- class placing once. Their club report does not multiply a placing by the
-- number shown and does not add breed/show award points.
--
-- Seed this as a dated portal schedule so the existing calculator remains
-- club-specific and every other breed club keeps its own effective rules.
insert into public.sweepstakes_point_schedules (
  portal_club_id,
  effective_on,
  rules,
  notes
)
select
  club.id,
  date '1900-01-01',
  jsonb_build_object(
    'show_type', 'regular',
    'class_points_model', 'FLAT_BY_PLACING',
    'placements', jsonb_build_array(
      jsonb_build_object('place', 1, 'points', 6),
      jsonb_build_object('place', 2, 'points', 4),
      jsonb_build_object('place', 3, 'points', 3),
      jsonb_build_object('place', 4, 'points', 2),
      jsonb_build_object('place', 5, 'points', 1)
    ),
    'awards', '[]'::jsonb
  ),
  'ASCRA class placements are flat 6/4/3/2/1; no automatic award points.'
from public.sweepstakes_portal_clubs club
where club.normalized_name =
  'american standard chinchilla rabbit association'
on conflict (portal_club_id, effective_on) do nothing;
