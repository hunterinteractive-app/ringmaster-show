-- Preserve any Commercial preset sections created between releases by adding
-- the newly included Mini Californian breed without disturbing other IDs.
update public.show_sections ss
set allowed_breed_ids = array_append(
  coalesce(ss.allowed_breed_ids, array[]::uuid[]),
  breed.id
)
from public.breeds breed
where ss.breed_scope = 'grouped_commercial'
  and breed.species::text = 'rabbit'
  and lower(btrim(breed.name)) = lower('Mini Californian')
  and not breed.id = any(coalesce(ss.allowed_breed_ids, array[]::uuid[]));
