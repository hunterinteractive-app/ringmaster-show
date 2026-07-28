-- NSRC Article II, Rule 6(B)-(C): variety and breed awards are multiplied
-- by their shown count.  BOV/BOB use two points per rabbit; BOSV/BOSB use
-- one point per rabbit.
update public.breed_rules_matrix
set
  bov_points = 2,
  bosv_points = 1,
  bob_points = 2,
  bosb_points = 1,
  updated_at = now()
where lower(btrim(breed_name)) = 'silver';
