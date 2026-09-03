-- Run this once in the Supabase SQL Editor.
--
-- Corrects the historical rabbit-breed typo:
--   Champagne d'Argente  ->  Champagne d'Argent
--
-- The transaction updates the shared breed catalog plus every operational
-- public base-table text column named `breed` or `breed_name`. Backup tables
-- are intentionally left unchanged. If any unique constraint would be
-- violated, PostgreSQL aborts the transaction and no partial update remains.

begin;

create temporary table champagne_dargent_update_audit (
  table_name text not null,
  operation text not null,
  rows_affected bigint not null
);

do $fix$
declare
  target record;
  affected bigint;
begin
  -- Two rules exist because the later standard fallback was accidentally
  -- inserted under the typo while an older placeholder already used the
  -- correct spelling. Preserve the configured fallback row and discard only
  -- the known placeholder before renaming the configured row below.
  if exists (
    select 1
    from public.breed_rules_matrix
    where lower(replace(breed_name, '’', '''')) = 'champagne d''argent'
  ) and exists (
    select 1
    from public.breed_rules_matrix
    where lower(replace(breed_name, '’', '''')) = 'champagne d''argente'
  ) then
    if not exists (
      select 1
      from public.breed_rules_matrix
      where lower(replace(breed_name, '’', '''')) = 'champagne d''argent'
        and rule_source = 'Pending'
        and status = 'fallback'
        and notes = 'No rules captured yet.'
    ) or not exists (
      select 1
      from public.breed_rules_matrix
      where lower(replace(breed_name, '’', '''')) = 'champagne d''argente'
        and rule_source = 'RingMaster standard rabbit fallback schedule'
    ) then
      raise exception
        'Champagne d''Argent rule rows differ from the expected placeholder/fallback pair; no changes were made';
    end if;

    delete from public.breed_rules_matrix
    where lower(replace(breed_name, '’', '''')) = 'champagne d''argent'
      and rule_source = 'Pending'
      and status = 'fallback'
      and notes = 'No rules captured yet.';

    get diagnostics affected = row_count;
    insert into champagne_dargent_update_audit
      (table_name, operation, rows_affected)
    values (
      'breed_rules_matrix',
      'removed obsolete correct-name placeholder',
      affected
    );
  end if;

  update public.breeds
  set name = 'Champagne d''Argent'
  where species = 'rabbit'
    and lower(replace(name, '’', '''')) = 'champagne d''argente';

  get diagnostics affected = row_count;
  insert into champagne_dargent_update_audit
    (table_name, operation, rows_affected)
  values ('breeds', 'updated name', affected);

  -- Entries for completed shows are protected by a lock trigger. Disable only
  -- that trigger while this spelling-only maintenance update runs. ALTER TABLE
  -- holds an exclusive lock, and any error rolls the transaction (including
  -- the trigger state) back automatically.
  alter table public.entries
    disable trigger prevent_entry_changes_when_locked;

  update public.entries
  set breed = 'Champagne d''Argent'
  where lower(replace(breed, '’', '''')) = 'champagne d''argente';

  get diagnostics affected = row_count;
  insert into champagne_dargent_update_audit
    (table_name, operation, rows_affected)
  values ('entries', 'updated breed', affected);

  alter table public.entries
    enable trigger prevent_entry_changes_when_locked;

  for target in
    select c.relname as table_name, a.attname as column_name
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n
      on n.oid = c.relnamespace
    join pg_catalog.pg_attribute a
      on a.attrelid = c.oid
     and a.attnum > 0
     and not a.attisdropped
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and a.attname in ('breed', 'breed_name')
      and pg_catalog.format_type(a.atttypid, a.atttypmod)
          in ('text', 'character varying')
      and c.relname not like '%backup%'
      and c.relname <> 'entries'
    order by c.relname, a.attname
  loop
    execute format(
      'update public.%I set %I = $1 '
      'where lower(replace(%I, $2, $3)) = $4',
      target.table_name,
      target.column_name,
      target.column_name
    )
    using
      'Champagne d''Argent',
      '’',
      '''',
      'champagne d''argente';

    get diagnostics affected = row_count;

    if affected > 0 then
      insert into champagne_dargent_update_audit
        (table_name, operation, rows_affected)
      values (
        target.table_name,
        format('updated %I', target.column_name),
        affected
      );
    end if;
  end loop;

  -- Refuse to commit if any operational base-table typo survived.
  for target in
    select c.relname as table_name, a.attname as column_name
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n
      on n.oid = c.relnamespace
    join pg_catalog.pg_attribute a
      on a.attrelid = c.oid
     and a.attnum > 0
     and not a.attisdropped
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and a.attname in ('breed', 'breed_name')
      and pg_catalog.format_type(a.atttypid, a.atttypmod)
          in ('text', 'character varying')
      and c.relname not like '%backup%'
  loop
    execute format(
      'select count(*) from public.%I '
      'where lower(replace(%I, $1, $2)) = $3',
      target.table_name,
      target.column_name
    )
    into affected
    using '’', '''', 'champagne d''argente';

    if affected > 0 then
      raise exception
        'Spelling correction incomplete: %.% still contains % row(s)',
        target.table_name,
        target.column_name,
        affected;
    end if;
  end loop;

  if exists (
    select 1
    from public.breeds
    where species = 'rabbit'
      and lower(replace(name, '’', '''')) = 'champagne d''argente'
  ) then
    raise exception 'Spelling correction incomplete in public.breeds.name';
  end if;
end
$fix$;

commit;

-- The SQL Editor displays this summary after a successful commit.
select table_name, operation, rows_affected
from champagne_dargent_update_audit
where rows_affected > 0
order by table_name, operation;
