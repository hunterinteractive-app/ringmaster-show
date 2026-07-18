create or replace view public.v_sweepstakes_pdf_rows
with (security_invoker = true)
as
select
  sr.show_id,
  sr.breed_name,
  sr.scope,
  sr.show_letter,
  sr.exhibitor_id,
  sr.exhibitor_name,
  concat_ws(
    ', ',
    nullif(e.address_line1, ''),
    nullif(e.city, ''),
    nullif(e.state, ''),
    nullif(e.zip, '')
  ) as exhibitor_address,
  sr.class_points,
  sr.class_points as arba_class_points,
  sr.variety_points,
  sr.group_points,
  sr.bob_points,
  sr.bis_points,
  sr.fur_points,
  sr.total_points,
  sr.calculation_version,
  sr.rule_source,
  sr.verification_status,
  sr.engine_type,
  ''::text as arba_sanction_number,
  ''::text as national_club_sanction_number,
  c.name as host_club_name,
  s.location_name as show_location,
  ''::text as secretary_name,
  s.secretary_email,
  s.secretary_phone,
  row_number() over (
    partition by sr.show_id, sr.breed_name, sr.scope, sr.show_letter
    order by sr.total_points desc, sr.class_points desc, sr.exhibitor_name
  ) as rank
from public.sweepstakes_results sr
left join public.exhibitors e on e.id::text = sr.exhibitor_id
left join public.shows s on s.id = sr.show_id
left join public.clubs c on c.id = s.club_id
where sr.calculation_version in ('v2', 'cavy-fixed-v1');
