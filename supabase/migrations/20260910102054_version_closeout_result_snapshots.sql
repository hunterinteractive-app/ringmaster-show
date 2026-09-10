-- A cheap, exact invalidation token for the result projection. One bump per
-- affected show per statement, including deletes/moves; unrelated shows do not
-- invalidate each other. Catalog/profile changes invalidate the shared token.
create schema if not exists report_generation_private;
create table report_generation_private.result_revisions (
  scope_id uuid primary key,
  revision bigint not null default 1
);
alter table report_generation_private.result_revisions enable row level security;
revoke all on table report_generation_private.result_revisions from public, anon, authenticated;

create function report_generation_private.invalidate_result_rows()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_query text;
begin
  if TG_ARGV[0] = 'global' then
    insert into report_generation_private.result_revisions(scope_id)
      values ('00000000-0000-0000-0000-000000000000')
    on conflict (scope_id) do update set revision = result_revisions.revision + 1;
  else
    v_query := case TG_OP
      when 'INSERT' then 'select distinct show_id from new_rows'
      when 'DELETE' then 'select distinct show_id from old_rows'
      else 'select show_id from new_rows union select show_id from old_rows' end;
    execute 'insert into report_generation_private.result_revisions(scope_id)
      select show_id from (' || v_query || ') affected where show_id is not null
      order by show_id on conflict (scope_id) do update
      set revision = result_revisions.revision + 1';
  end if;
  return null;
end;
$$;
revoke all on function report_generation_private.invalidate_result_rows() from public, anon, authenticated;

do $$
declare v_table text; v_kind text;
begin
  foreach v_table in array array['entries', 'show_sections', 'show_exhibitor_numbers',
      'exhibitors', 'breeds', 'varieties', 'variety_groups'] loop
    v_kind := case when v_table in ('entries','show_sections','show_exhibitor_numbers')
      then 'show' else 'global' end;
    execute format('create trigger report_results_insert after insert on public.%I
      referencing new table as new_rows for each statement
      execute function report_generation_private.invalidate_result_rows(%L)', v_table, v_kind);
    execute format('create trigger report_results_update after update on public.%I
      referencing new table as new_rows old table as old_rows for each statement
      execute function report_generation_private.invalidate_result_rows(%L)', v_table, v_kind);
    execute format('create trigger report_results_delete after delete on public.%I
      referencing old table as old_rows for each statement
      execute function report_generation_private.invalidate_result_rows(%L)', v_table, v_kind);
  end loop;
end;
$$;

create function public.get_report_result_revision(p_show_id uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select revision::text from report_generation_private.result_revisions
    where scope_id = p_show_id), '0') || ':' ||
    coalesce((select revision::text from report_generation_private.result_revisions
    where scope_id = '00000000-0000-0000-0000-000000000000'), '0');
$$;
-- Worker-only: browser report loads are always fresh and retain their own RLS.
revoke all on function public.get_report_result_revision(uuid) from public, anon, authenticated;
grant execute on function public.get_report_result_revision(uuid) to service_role;
