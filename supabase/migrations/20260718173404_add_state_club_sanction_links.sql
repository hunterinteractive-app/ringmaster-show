-- Give every active state association and state specialty club an actionable
-- destination. When a club does not publish its own sanction page, ARBA's live
-- club directory is used because it carries the current secretary/contact.

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
  'club_directory',
  'Find club contact on ARBA',
  'https://arba.net/club-search/',
  'No public club sanction page was found. Use the official ARBA club directory for the current secretary and sanction contact.',
  true,
  now()
from public.breed_clubs club
where club.club_type in ('STATE BREED CLUB', 'STATE CLUB')
  and club.is_active = true
  and not exists (
    select 1
    from public.breed_club_sanction_links existing
    where existing.breed_club_id = club.id
      and existing.is_active = true
  );

-- Replace directory fallbacks with verified official club destinations where
-- the state organization publishes a usable site or sanction/sweepstakes page.
with official_destinations(club_name, link_type, label, url, notes) as (
  values
    ('CALIFORNIA STATE RABBIT & CAVY BREEDERS ASSOCIATION', 'sanction_info', 'State sanctions and sweepstakes', 'https://www.calstatercba.com/sweepstakes', 'Official California State Rabbit & Cavy Breeders Association sweepstakes page.'),
    ('FLORIDA STATE RABBIT & CAVY BREEDERS ASSOCIATION', 'sanction_info', 'Open state club website', 'https://www.fsrcba.com/', 'Official Florida State Rabbit & Cavy Breeders Association website.'),
    ('INDIANA STATE RBA', 'sanction_info', 'Open state club website', 'https://www.isrba.com/', 'Official Indiana State Rabbit Breeders Association website.'),
    ('KANSAS STATE RBA', 'sanction_info', 'Open state club website', 'https://www.ksrba.com/', 'Official Kansas State Rabbit Breeders Association website.'),
    ('MICHIGAN STATE RBA', 'sanction_info', 'Open state club website', 'https://msrba.org/', 'Official Michigan State Rabbit Breeders Association website.'),
    ('NEW YORK RABBIT & CAVY BREEDERS ASSOCIATION', 'sanction_info', 'State sanctions and sweepstakes', 'https://nyrcba.com/sweepstakes/', 'Official New York Rabbit & Cavy Breeders Association sweepstakes page.'),
    ('PENNSYLVANIA STATE RBA', 'sanction_info', 'Open state club website', 'https://www.pasrba.org/', 'Official Pennsylvania State Rabbit Breeders Association website.'),
    ('TEXAS RBA', 'sanction_info', 'Open state club website', 'https://www.trba.net/', 'Official Texas Rabbit Breeders Association website.'),
    ('WASHINGTON STATE RBA', 'sanction_info', 'Open state club website', 'https://wsrba.net/', 'Official Washington State Rabbit Breeders Association website.'),
    ('OREGON LEAGUE OF RABBIT & CAVY BREEDERS', 'sanction_info', 'Open state club website', 'http://www.olrcb.net/', 'Official Oregon League of Rabbit & Cavy Breeders website published in its show materials.'),
    ('TEXAS CALIFORNIAN RABBIT SPECIALTY CLUB', 'sanction_info', 'Open specialty club website', 'https://texascals.org/', 'Official Texas Californian Rabbit Specialty Club website.')
)
update public.breed_club_sanction_links link
set
  link_type = destination.link_type,
  label = destination.label,
  url = destination.url,
  notes = destination.notes,
  is_active = true,
  last_verified_at = now(),
  updated_at = now()
from public.breed_clubs club
join official_destinations destination
  on upper(btrim(destination.club_name)) = upper(btrim(club.club_name))
where link.breed_club_id = club.id
  and club.club_type in ('STATE BREED CLUB', 'STATE CLUB')
  and club.is_active = true;
