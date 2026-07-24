-- Some historic exhibitor artifacts were saved with `species` as a one-item
-- JSON array (for example `["rabbit"]`) instead of the scalar value expected
-- by the species-scoped closeout dashboard. Normalize on every write before
-- scope keys are derived, and repair the existing rows.

create or replace function public.normalize_exhibitor_artifact_species()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_species text;
begin
  if new.report_name::text not in ('exhibitor_report', 'checkin_sheet', 'legs')
     or jsonb_typeof(new.metadata -> 'species') <> 'array'
     or jsonb_array_length(new.metadata -> 'species') <> 1 then
    return new;
  end if;

  v_species := lower(nullif(btrim(new.metadata -> 'species' ->> 0), ''));
  if v_species in ('rabbit', 'cavy') then
    new.metadata := new.metadata || jsonb_build_object('species', v_species);
  end if;
  return new;
end;
$function$;

drop trigger if exists a_normalize_exhibitor_artifact_species
  on public.show_report_artifacts;

create trigger a_normalize_exhibitor_artifact_species
before insert or update of metadata, report_name
on public.show_report_artifacts
for each row
execute function public.normalize_exhibitor_artifact_species();

update public.show_report_artifacts
set metadata = metadata || jsonb_build_object(
  'species', lower(metadata -> 'species' ->> 0)
)
where report_name in (
  'exhibitor_report'::public.report_type,
  'checkin_sheet'::public.report_type,
  'legs'::public.report_type
)
  and jsonb_typeof(metadata -> 'species') = 'array'
  and jsonb_array_length(metadata -> 'species') = 1
  and lower(metadata -> 'species' ->> 0) in ('rabbit', 'cavy');
