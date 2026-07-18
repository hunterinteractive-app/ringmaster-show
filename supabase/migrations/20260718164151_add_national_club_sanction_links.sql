-- Populate every active national breed club with its most direct currently
-- published sanction request, checkout, form, or official sanction-info page.
-- Sources were verified against ARBA's National Specialty Clubs directory and
-- the linked official club sites on 2026-07-18.

with verified_links(breed_name, link_type, label, url, notes) as (
  values
    ('American', 'checkout', 'Purchase sanction online', 'https://americanrabbits.org/shop/', 'Official club checkout with Open/Youth sanction products.'),
    ('American Chinchilla', 'sanction_info', 'Sanction information', 'https://www.acrba.net', 'Official national club website published by ARBA.'),
    ('American Fuzzy Lop', 'checkout', 'Request sanction online', 'https://www.aflrc.com/blank-8', 'Official club sanctions page.'),
    ('American Sable', 'sanction_info', 'ARBA sanction information', 'https://arba.net/national-specialty-clubs/', 'ARBA currently publishes the club sanction instructions; no separate public club checkout was found.'),
    ('Argente Brun', 'sanction_info', 'Sanction information', 'https://www.aabrc.org', 'Official national club website published by ARBA.'),
    ('Belgian Hare', 'sanction_info', 'Sanction information', 'https://www.belgianhareclub.com/', 'Official national club website published by ARBA.'),
    ('Beveren', 'sanction_info', 'Sanction information', 'https://www.abprs.com/', 'Official national club website published by ARBA.'),
    ('Blanc de Hotot', 'sanction_info', 'Sanction information', 'https://www.hrbi.online/', 'Official national club website published by ARBA.'),
    ('Blue Holicer', 'sanction_info', 'Sanction information', 'http://blueholicerrabbitclub.com', 'Official national club website published by ARBA.'),
    ('Britannia Petite', 'sanction_info', 'Sanction information', 'https://www.abprs.com/', 'Official national club website published by ARBA.'),
    ('Californian', 'sanction_info', 'Sanction information', 'https://nationalcrsc.org', 'Official national club website published by ARBA.'),
    ('Cavy', 'sanction_info', 'Request sanction', 'https://www.acbaonline.com', 'Official ACBA site; ARBA directs sanction requests to its website form.'),
    ('Champagne d''Argent', 'sanction_info', 'Sanction information', 'https://www.cdarf.us/', 'Official national club website published by ARBA.'),
    ('Checkered Giant', 'sanction_info', 'Sanction information', 'https://www.checkeredgiant.org/', 'Official national club website with sanction request instructions.'),
    ('Cinnamon', 'sanction_info', 'ARBA sanction information', 'https://arba.net/national-specialty-clubs/', 'ARBA currently publishes the club sanction instructions; no separate public club checkout was found.'),
    ('Creme d''Argent', 'sanction_info', 'Sanction information', 'https://www.cremedargent.com', 'Official national club website published by ARBA.'),
    ('Czech Frosty', 'sanction_info', 'Sanction information', 'https://czechfrosty.com/', 'Official national club website published by ARBA.'),
    ('Dutch', 'sanction_info', 'Sanction information', 'https://www.dutchrabbit.com/index.html', 'Official national club website published by ARBA.'),
    ('Dwarf Hotot', 'sanction_info', 'Sanction information', 'https://www.adhrc.com/', 'Official national club website published by ARBA.'),
    ('Dwarf Papillon', 'sanction_info', 'Sanction information', 'https://dwarfpapillon.com', 'Official national club website published by ARBA.'),
    ('English Angora', 'sanction_info', 'Sanction information', 'https://www.nationalangorarabbitbreeders.com/', 'One sanction covers the four Angora breeds.'),
    ('English Lop', 'sanction_info', 'Sanction information', 'https://loprabbitclubofamerica.org', 'Official LRCA site for English and French Lop sanctions.'),
    ('English Spot', 'sanction_info', 'Sanction information', 'https://americanenglishspot.weebly.com/', 'Official national club website published by ARBA.'),
    ('Flemish Giant', 'sanction_info', 'Sanction information', 'https://nffgrb.org', 'Official national club website published by ARBA.'),
    ('Florida White', 'sanction_info', 'Sanction information', 'https://www.fwrba.net/', 'Official national club website published by ARBA.'),
    ('French Angora', 'sanction_info', 'Sanction information', 'https://www.nationalangorarabbitbreeders.com/', 'One sanction covers the four Angora breeds.'),
    ('French Lop', 'sanction_info', 'Sanction information', 'https://loprabbitclubofamerica.org', 'Official LRCA site for English and French Lop sanctions.'),
    ('Giant Angora', 'sanction_info', 'Sanction information', 'https://www.nationalangorarabbitbreeders.com/', 'One sanction covers the four Angora breeds.'),
    ('Giant Chinchilla', 'sanction_info', 'Sanction information', 'https://giantchinchillarabbits.com', 'Official national club website published by ARBA.'),
    ('Harlequin', 'sanction_info', 'Sanction information', 'https://americanharlequinrabbitclub.weebly.com/', 'Official national club website published by ARBA.'),
    ('Havana', 'sanction_info', 'Sanction information', 'http://www.havanarb.net/', 'Official national club website published by ARBA.'),
    ('Himalayan', 'sanction_info', 'Sanction information', 'https://www.himalayanrabbit.com/', 'Official national club website published by ARBA.'),
    ('Holland Lop', 'sanction_info', 'Sanction information', 'https://www.hlrsc.org', 'Official national club website published by ARBA.'),
    ('Jersey Wooly', 'sanction_info', 'Sanction information', 'https://jerseywooly.org/', 'Official national club website with current sanction payment instructions.'),
    ('Lilac', 'sanction_info', 'Sanction information', 'https://www.nlrba.org/', 'Official national club website published by ARBA.'),
    ('Lionhead', 'checkout', 'Request sanction online', 'https://pci.jotform.com/form/221967946795175', 'Official North American Lionhead Rabbit Club sanction request form.'),
    ('Mini Californian', 'sanction_info', 'Sanction information', 'https://nationalcrsc.org', 'Official national club website published by ARBA.'),
    ('Mini Lop', 'sanction_info', 'Sanction information', 'https://www.amlrcsweeps.com/', 'Official club sweepstakes and sanction site published by ARBA.'),
    ('Mini Rex', 'sanction_info', 'Sanction information', 'https://www.nmrrc.net/', 'Official national club website published by ARBA.'),
    ('Mini Satin', 'checkout', 'Request sanction online', 'https://easy2showclub.com/sanctions', 'Official ASRBA online sanction checkout for Satin and Mini Satin.'),
    ('Netherland Dwarf', 'sanction_info', 'Sanction information', 'https://www.andrc.com/', 'Official national club website published by ARBA.'),
    ('New Zealand', 'sanction_info', 'Sanction information', 'https://newzealandrabbitclub.org', 'Official national club website published by ARBA.'),
    ('Palomino', 'sanction_info', 'Sanction information', 'https://www.palominorabbits.org/', 'Official national club website published by ARBA.'),
    ('Polish', 'sanction_info', 'Sanction information', 'https://www.americanpolishrabbitclub.com/', 'Official national club website published by ARBA.'),
    ('Rex', 'checkout', 'Request sanction online', 'https://www.nationalrexrc.org/online-sanction-request', 'Official National Rex Rabbit Club online sanction request.'),
    ('Rhinelander', 'sanction_info', 'Sanction information', 'http://www.rhinelanderrabbits.com/', 'Official national club website published by ARBA.'),
    ('Satin', 'checkout', 'Request sanction online', 'https://easy2showclub.com/sanctions', 'Official ASRBA online sanction checkout for Satin and Mini Satin.'),
    ('Satin Angora', 'sanction_info', 'Sanction information', 'https://www.nationalangorarabbitbreeders.com/', 'One sanction covers the four Angora breeds.'),
    ('Silver', 'sanction_form', 'Download sanction form', 'https://www.silverrabbitclub.com/_files/ugd/8ffb73_b2621b26ffe24c5488d5d49e8ab8c768.pdf', 'Official National Silver Rabbit Club sanction request form.'),
    ('Silver Fox', 'sanction_form', 'Download sanction form', 'https://www.nsfrc.com/sanction_request_form.pdf', 'Official National Silver Fox Rabbit Club sanction request form.'),
    ('Silver Marten', 'sanction_info', 'Sanction information', 'https://www.silvermarten.org/', 'Official national club website published by ARBA.'),
    ('Standard Chinchilla', 'sanction_info', 'Sanction information', 'https://linktr.ee/standardchinchillarabbit', 'Official club link directory published by ARBA.'),
    ('Tan', 'sanction_info', 'Sanction information', 'https://www.atrsc.org/', 'Official national club website published by ARBA.'),
    ('Thrianta', 'sanction_info', 'Sanction information', 'https://www.americanthriantarba.com/', 'Official national club website published by ARBA.')
)
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
  link.link_type,
  link.label,
  link.url,
  link.notes,
  true,
  now()
from verified_links link
join public.breed_clubs club
  on club.breed_name = link.breed_name
 and club.club_type = 'National Breed Clubs'
 and club.is_active = true
where not exists (
  select 1
  from public.breed_club_sanction_links existing
  where existing.breed_club_id = club.id
    and existing.url = link.url
);
