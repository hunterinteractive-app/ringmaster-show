-- Replace general club homepages with the direct sanction destinations
-- supplied and verified by the directory administrator on 2026-07-18.

with corrected_links(breed_name, link_type, label, url) as (
  values
    ('American Chinchilla', 'sanction_request', 'Request sanction', 'https://www.acrba.net/sanctions'),
    ('Argente Brun', 'sanction_request', 'Request sanction', 'https://www.aabrc.org/sanction-applications'),
    ('Belgian Hare', 'sanction_request', 'Request sanction', 'https://www.belgianhareclub.com/show-sanctions.html'),
    ('Beveren', 'sanction_info', 'ARBA sanction information', 'https://arba.net/national-specialty-clubs/'),
    ('Blanc de Hotot', 'sanction_request', 'Request sanction', 'https://www.hrbi.online/sanction-request.html'),
    ('Blue Holicer', 'sanction_request', 'Request sanction', 'https://www.blueholicerrabbitclub.com/sanction-a-show'),
    ('Britannia Petite', 'sanction_request', 'Request sanction', 'https://www.abprs.com/sanction-application'),
    ('Californian', 'sanction_form', 'Sanction forms', 'https://nationalcrsc.org/forms'),
    ('Mini Californian', 'sanction_form', 'Sanction forms', 'https://nationalcrsc.org/forms'),
    ('Cavy', 'sanction_request', 'Request sanction', 'https://www.acbaonline.com/request-sanction'),
    ('Champagne d''Argent', 'sanction_form', 'Sanction forms', 'https://www.cdarf.us/forms'),
    ('Checkered Giant', 'sanction_form', 'Download sanction form', 'https://www.checkeredgiant.org/_files/ugd/d30027_2a78da36d0a34bc6a6d6528ad4276193.pdf'),
    ('Cinnamon', 'sanction_form', 'Sanction forms', 'https://www.cinnamonrabbitbreedersassociation.com/forms'),
    ('Creme d''Argent', 'sanction_request', 'Request sanction', 'https://www.cremedargent.com/sanction-request'),
    ('Czech Frosty', 'sanction_request', 'Request sanction', 'https://www.czechfrosty.com/sanction-a-show'),
    ('Dutch', 'sanction_request', 'Request sanction', 'https://www.dutchrabbit.com/course-2-1/lesson-1-problemsolving-t6xn2-gk86j-zyfjp'),
    ('Dwarf Hotot', 'sanction_info', 'Sanction information', 'https://www.adhrc.com/Info.html'),
    ('Dwarf Papillon', 'checkout', 'Purchase sanction', 'https://dwarfpapillon.com/product-category/sanction-forms-and-requests/'),
    ('English Angora', 'sanction_request', 'Request sanction', 'https://www.nationalangorarabbitbreeders.com/show-sanctions.php'),
    ('French Angora', 'sanction_request', 'Request sanction', 'https://www.nationalangorarabbitbreeders.com/show-sanctions.php'),
    ('Giant Angora', 'sanction_request', 'Request sanction', 'https://www.nationalangorarabbitbreeders.com/show-sanctions.php'),
    ('Satin Angora', 'sanction_request', 'Request sanction', 'https://www.nationalangorarabbitbreeders.com/show-sanctions.php'),
    ('English Lop', 'sanction_request', 'Request sanction', 'https://loprabbitclubofamerica.org/sanction-form'),
    ('French Lop', 'sanction_request', 'Request sanction', 'https://loprabbitclubofamerica.org/sanction-form'),
    ('English Spot', 'sanction_form', 'Sanction forms', 'https://americanenglishspot.weebly.com/forms.html'),
    ('Flemish Giant', 'sanction_request', 'Request sanction', 'https://nffgrb.org/sanction-requests'),
    ('Florida White', 'sanction_info', 'ARBA sanction information', 'https://arba.net/national-specialty-clubs/'),
    ('Giant Chinchilla', 'sanction_form', 'Download sanction form', 'https://www.giantchinchillarabbit.com/uploads/1/4/0/6/14061336/sanction_form.pdf'),
    ('Harlequin', 'sanction_request', 'Request sanction', 'https://americanharlequinrabbitclub.weebly.com/sanctions.html'),
    ('Havana', 'sanction_form', 'Sanction forms', 'http://www.havanarb.net/forms.html'),
    ('Himalayan', 'sanction_form', 'Download sanction form', 'https://www.himalayanrabbit.com/_files/ugd/82f176_e7228f0fd2204e0ebc6d5d40eeeebef5.pdf'),
    ('Holland Lop', 'checkout', 'Purchase sanction', 'https://www.hlrsc.org/shop'),
    ('Jersey Wooly', 'sanction_info', 'Sanctions and sweepstakes', 'https://jerseywooly.org/sweepstakes-%26-sanctions'),
    ('Lilac', 'sanction_info', 'Sanctions and sweepstakes', 'https://www.nlrba.org/sanctions-sweepstakes'),
    ('Mini Lop', 'sanction_request', 'Request sanction', 'https://www.amlrcsweeps.com/sanction-request-form.html'),
    ('Mini Rex', 'sanction_request', 'Request sanction', 'https://www.nmrrc.net/sanction-request.html'),
    ('Mini Satin', 'checkout', 'Purchase sanction', 'https://easy2showclub.com/sanctions'),
    ('Satin', 'checkout', 'Purchase sanction', 'https://easy2showclub.com/sanctions'),
    ('Netherland Dwarf', 'sanction_request', 'Request sanction', 'https://www.andrc.com/Show_Sanctions.php'),
    ('New Zealand', 'sanction_request', 'Request sanction', 'https://newzealandrabbitclub.org/sanction-request'),
    ('Palomino', 'sanction_request', 'Request sanction', 'https://www.palominorabbits.org/online_sanction.htm'),
    ('Polish', 'sanction_request', 'Request sanction', 'https://www.americanpolishrabbitclub.com/sanction'),
    ('Rex', 'checkout', 'Purchase sanction', 'https://www.nationalrexrc.org/shop'),
    ('Rhinelander', 'sanction_request', 'Request sanction', 'https://rhinelanderrabbits.com/sanctions/'),
    ('Silver Marten', 'sanction_info', 'ARBA sanction information', 'https://arba.net/national-specialty-clubs/'),
    ('Tan', 'sanction_request', 'Request sanction', 'https://www.atrsc.org/copy-of-breed-history-1'),
    ('Thrianta', 'sanction_form', 'Sanction forms and guidelines', 'https://www.americanthriantarba.com/forms-and-guidelines.html')
)
update public.breed_club_sanction_links link
set
  link_type = corrected.link_type,
  label = corrected.label,
  url = corrected.url,
  notes = 'Direct sanction destination verified by the directory administrator on 2026-07-18.',
  is_active = true,
  last_verified_at = now(),
  updated_at = now()
from public.breed_clubs club
join corrected_links corrected
  on corrected.breed_name = club.breed_name
where link.breed_club_id = club.id
  and club.club_type = 'National Breed Clubs'
  and club.is_active = true;
