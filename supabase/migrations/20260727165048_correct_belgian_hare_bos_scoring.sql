-- The American Belgian Hare Club awards BOS at one half of the entire breed
-- count, not one half of the same-sex count.
update public.breed_rules_matrix
set bos_basis = 'BREED_COUNT',
    updated_at = now()
where lower(btrim(breed_name)) = 'belgian hare';
