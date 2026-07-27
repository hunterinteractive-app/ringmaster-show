-- ACBA is represented as the National Club sanction for Cavy. Its delivery
-- package also needs the section-level Exhibitor by Breed and Details by
-- Breed reports. Seed those companion artifacts whenever the normal Cavy
-- sweepstakes artifact is created.
create or replace function public.seed_acba_section_report_artifacts()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.report_name <> 'sweepstakes_report'::public.report_type
     or upper(btrim(coalesce(new.metadata ->> 'sanctioning_body', ''))) <> 'NATIONAL CLUB'
     or lower(btrim(coalesce(new.metadata ->> 'breed_name', ''))) <> 'cavy' then
    return new;
  end if;

  insert into public.show_report_artifacts (
    show_id,
    finalize_run_id,
    report_name,
    artifact_status,
    metadata,
    is_current,
    scope_key,
    section_ids
  )
  select
    new.show_id,
    new.finalize_run_id,
    report_name,
    new.artifact_status,
    new.metadata,
    new.is_current,
    new.scope_key,
    new.section_ids
  from unnest(
    array[
      'details_by_breed'::public.report_type,
      'exh_by_breed'::public.report_type
    ]
  ) as reports(report_name)
  where not exists (
    select 1
    from public.show_report_artifacts existing
    where existing.show_id = new.show_id
      and existing.finalize_run_id = new.finalize_run_id
      and existing.report_name = reports.report_name
      and existing.metadata ->> 'section_id' = new.metadata ->> 'section_id'
      and lower(btrim(coalesce(existing.metadata ->> 'breed_name', ''))) = 'cavy'
      and upper(btrim(coalesce(existing.metadata ->> 'sanctioning_body', ''))) = 'NATIONAL CLUB'
  );

  return new;
end;
$function$;

drop trigger if exists seed_acba_section_report_artifacts
  on public.show_report_artifacts;

create trigger seed_acba_section_report_artifacts
after insert on public.show_report_artifacts
for each row execute function public.seed_acba_section_report_artifacts();
