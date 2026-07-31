-- Keep the secretary's Breed Counts table in sync with Judging Lineup.
-- A scratched entry is excluded whether it is identified by the modern
-- scratched_at timestamp or the legacy status value.
create or replace function public.report_entries_by_breed_section(
  p_show_id uuid,
  p_include_scratched boolean
)
returns table(
  section_id uuid,
  breed text,
  variety text,
  class_name text,
  sex text,
  exhibitor_id uuid,
  species text,
  scratched_at timestamp with time zone
)
language sql
security definer
set search_path = ''
as $function$
  select
    e.section_id,
    e.breed,
    e.variety,
    e.class_name,
    e.sex,
    e.exhibitor_id,
    e.species,
    e.scratched_at
  from public.entries e
  where e.show_id = p_show_id
    and (
      p_include_scratched
      or (
        e.scratched_at is null
        and coalesce(e.status, '') <> 'scratched'
      )
    );
$function$;

revoke all on function public.report_entries_by_breed_section(uuid, boolean)
  from public, anon;
grant execute on function public.report_entries_by_breed_section(uuid, boolean)
  to authenticated, service_role;
