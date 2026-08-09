-- Supply the established standard rabbit placement schedule for recognized
-- breeds that predate an individual national-club rule.  Without a matrix
-- row, the legacy calculator quietly multiplies every placement by zero.
--
-- This is intentionally a data fallback rather than a club-specific rule:
-- a national-club schedule, when one exists, still takes precedence in the
-- portal calculator.  We exclude generic show classes (Market, Meat Pen,
-- and the Other-* buckets) because they are not rabbit breeds.
insert into public.breed_rules_matrix (
  breed_name,
  engine_family,
  class_points_model,
  placement_depth,
  multiplier_type,
  place_1, place_2, place_3, place_4, place_5,
  uses_variety_points, uses_group_points, uses_bob_points, uses_bos_points,
  uses_bis_points, uses_ris_points, uses_fur_points, uses_best4class_points,
  uses_participation_points,
  bov_points, bosv_points, bog_points, bosg_points, bob_points, bosb_points,
  bis_points, bris_points, fur_points, best4class_points, participation_points,
  bob_basis, bos_basis, bov_basis, bosv_basis, bis_basis, ris_basis, fur_basis,
  convention_override, national_override, specialty_override,
  membership_required, sanction_required, tracks_open, tracks_youth,
  rule_source, verification_status, status, notes
)
select
  missing.breed_name,
  template.engine_family,
  template.class_points_model,
  template.placement_depth,
  template.multiplier_type,
  template.place_1, template.place_2, template.place_3, template.place_4, template.place_5,
  template.uses_variety_points, template.uses_group_points, template.uses_bob_points, template.uses_bos_points,
  template.uses_bis_points, template.uses_ris_points, template.uses_fur_points, template.uses_best4class_points,
  template.uses_participation_points,
  template.bov_points, template.bosv_points, template.bog_points, template.bosg_points, template.bob_points, template.bosb_points,
  template.bis_points, template.bris_points, template.fur_points, template.best4class_points, template.participation_points,
  template.bob_basis, template.bos_basis, template.bov_basis, template.bosv_basis, template.bis_basis, template.ris_basis, template.fur_basis,
  false, false, false,
  false, false, true, true,
  'RingMaster standard rabbit fallback schedule', 'provisional', 'review',
  'Standard 6/4/3/2/1 placement multiplier schedule added for a breed without a dedicated rule.'
from public.breed_rules_matrix template
cross join (
  values
    ('Argenté St. Hubert'),
    ('Argenté St. Hubert (COD)'),
    ('Champagne d''Argente'),
    ('Creme d''Argente'),
    ('English spot'),
    ('Velveteen Lop (COD)')
) as missing(breed_name)
where template.breed_name = 'American Fuzzy Lop'
  and not exists (
    select 1
    from public.breed_rules_matrix existing
    where lower(existing.breed_name) = lower(missing.breed_name)
  );
