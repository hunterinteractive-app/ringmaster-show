alter table public.show_sections
  add column if not exists judging_date date;

-- Locked shows must remain immutable to application users, but existing
-- sections still need this one owner-run schema backfill. Disable only the
-- lock guard for the duration of the backfill; a migration failure rolls the
-- trigger state back with the transaction.
do $migration$
begin
  if exists (
    select 1
    from pg_catalog.pg_trigger as trigger_row
    join pg_catalog.pg_class as table_row
      on table_row.oid = trigger_row.tgrelid
    join pg_catalog.pg_namespace as schema_row
      on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and table_row.relname = 'show_sections'
      and trigger_row.tgname = 'prevent_show_section_changes_when_locked'
      and not trigger_row.tgisinternal
  ) then
    alter table public.show_sections
      disable trigger prevent_show_section_changes_when_locked;
  end if;
end;
$migration$;

update public.show_sections as section
set judging_date = show_row.start_date
from public.shows as show_row
where show_row.id = section.show_id
  and section.judging_date is null;

do $migration$
begin
  if exists (
    select 1
    from pg_catalog.pg_trigger as trigger_row
    join pg_catalog.pg_class as table_row
      on table_row.oid = trigger_row.tgrelid
    join pg_catalog.pg_namespace as schema_row
      on schema_row.oid = table_row.relnamespace
    where schema_row.nspname = 'public'
      and table_row.relname = 'show_sections'
      and trigger_row.tgname = 'prevent_show_section_changes_when_locked'
      and not trigger_row.tgisinternal
  ) then
    alter table public.show_sections
      enable trigger prevent_show_section_changes_when_locked;
  end if;
end;
$migration$;

create or replace function public.enforce_show_section_judging_date()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_start_date date;
  v_end_date date;
begin
  select show_row.start_date, show_row.end_date
  into v_start_date, v_end_date
  from public.shows as show_row
  where show_row.id = new.show_id;

  if not found then
    raise exception 'Show % was not found for show section', new.show_id;
  end if;

  -- Existing section-creation paths do not all supply a date yet. Defaulting
  -- to the first show day preserves compatibility and gives single-day shows
  -- their required locked date automatically.
  if new.judging_date is null or v_start_date = v_end_date then
    new.judging_date := v_start_date;
  end if;

  if new.judging_date < v_start_date or new.judging_date > v_end_date then
    raise exception 'Section judging date % must be between show dates % and %',
      new.judging_date,
      v_start_date,
      v_end_date;
  end if;

  return new;
end;
$function$;

drop trigger if exists enforce_show_section_judging_date
  on public.show_sections;

create trigger enforce_show_section_judging_date
before insert or update of show_id, judging_date
on public.show_sections
for each row
execute function public.enforce_show_section_judging_date();

alter table public.show_sections
  alter column judging_date set not null;

create or replace function public.realign_show_section_judging_dates()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if new.start_date is distinct from old.start_date
     or new.end_date is distinct from old.end_date then
    update public.show_sections
    set judging_date = case
      when new.start_date = new.end_date then new.start_date
      when judging_date between new.start_date and new.end_date then judging_date
      else new.start_date
    end
    where show_id = new.id;
  end if;

  return new;
end;
$function$;

drop trigger if exists realign_show_section_judging_dates
  on public.shows;

create trigger realign_show_section_judging_dates
after update of start_date, end_date
on public.shows
for each row
execute function public.realign_show_section_judging_dates();

comment on column public.show_sections.judging_date is
  'Calendar day on which this show section is judged; used by section-scoped reports and leg certificates.';
