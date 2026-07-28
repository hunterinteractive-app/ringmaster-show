-- NSRC Article II, Rule 6(A): placement points are multiplied by the number
-- of rabbits judged in the individual class, not the entire variety.
update public.breed_rules_matrix
set
  class_points_model = 'MULTIPLIER_BY_CLASS_SIZE',
  multiplier_type = 'ENTRY_COUNT',
  updated_at = now()
where lower(btrim(breed_name)) = 'silver';
