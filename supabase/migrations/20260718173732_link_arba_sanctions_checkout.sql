-- Link the system ARBA master record to ARBA's online sanction checkout.
insert into public.breed_club_sanction_links (
  breed_club_id,
  link_type,
  label,
  url,
  notes,
  is_active,
  last_verified_at
)
select
  club.id,
  'checkout',
  'Purchase ARBA sanction',
  'https://arba.net/product-category/arba-sanctions/',
  'Official ARBA sanctions checkout category verified by the directory administrator on 2026-07-18.',
  true,
  now()
from public.breed_clubs club
where upper(btrim(club.club_name)) = 'ARBA'
  and club.is_active = true
  and not exists (
    select 1
    from public.breed_club_sanction_links existing
    where existing.breed_club_id = club.id
      and existing.is_active = true
  );
