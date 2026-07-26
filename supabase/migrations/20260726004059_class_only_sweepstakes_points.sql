-- Sweepstakes standings are based exclusively on class placements. Keep award
-- records available for results and report display, but prevent every award
-- type from contributing points during finalization.
update public.point_award_scale
set award_points = 0,
    cavy_award_points = 0,
    updated_at = now();
