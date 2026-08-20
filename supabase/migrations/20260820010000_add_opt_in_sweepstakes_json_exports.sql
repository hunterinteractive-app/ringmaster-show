-- JSON exports are opt-in. Administrators control delivery by inserting an
-- enabled club/breed pair here; no club can enable this for itself.
alter type public.report_type add value if not exists 'sweepstakes_json_export';

create table if not exists public.sweepstakes_json_export_opt_ins (
  club_name text not null,
  breed_name text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (club_name, breed_name)
);

comment on table public.sweepstakes_json_export_opt_ins is
  'Admin-controlled opt-in list for machine-readable sweepstakes exports; use breed_name = ''*'' for every breed sanctioned to a club.';

alter table public.sweepstakes_json_export_opt_ins enable row level security;
revoke all on table public.sweepstakes_json_export_opt_ins from public, anon, authenticated;
grant select, insert, update, delete on table public.sweepstakes_json_export_opt_ins to service_role;

-- Preserve the established scope resolver for every existing artifact. The
-- JSON export has exactly the same scope rules as a Sweepstakes PDF, but its
-- report name must produce a distinct canonical identity and Storage object.
alter function public.resolve_closeout_artifact_scope(
  uuid, uuid, public.report_type, jsonb
) rename to resolve_closeout_artifact_scope_base;

create function public.resolve_closeout_artifact_scope(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_report_name public.report_type,
  p_metadata jsonb
)
returns table(
  is_repairable boolean,
  failure_reason text,
  scope_key text,
  section_ids uuid[],
  metadata jsonb,
  artifact_key text
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_base record;
  v_metadata jsonb;
  v_scope_key text;
begin
  if p_report_name <> 'sweepstakes_json_export'::public.report_type then
    return query
    select * from public.resolve_closeout_artifact_scope_base(
      p_show_id, p_finalize_run_id, p_report_name, p_metadata
    );
    return;
  end if;

  select * into v_base
  from public.resolve_closeout_artifact_scope_base(
    p_show_id, p_finalize_run_id, 'sweepstakes_report'::public.report_type, p_metadata
  );
  if not coalesce(v_base.is_repairable, false) then
    return query select v_base.is_repairable, v_base.failure_reason,
      v_base.scope_key, v_base.section_ids, v_base.metadata, v_base.artifact_key;
    return;
  end if;

  v_metadata := v_base.metadata;
  v_scope_key := public.closeout_artifact_scope_key(
    p_show_id, p_report_name, v_base.section_ids, v_metadata
  );
  v_metadata := v_metadata || jsonb_build_object('scope_key', v_scope_key);
  return query select true, null::text, v_scope_key, v_base.section_ids,
    v_metadata, public.closeout_artifact_identity(p_report_name, v_metadata);
end;
$function$;

revoke all on function public.resolve_closeout_artifact_scope(
  uuid, uuid, public.report_type, jsonb
) from public, anon;
grant execute on function public.resolve_closeout_artifact_scope(
  uuid, uuid, public.report_type, jsonb
) to authenticated, service_role;

-- Recompile the artifact trigger function so it resolves the wrapper above.
create or replace function public.set_closeout_artifact_scope_columns()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_scope record;
begin
  if new.finalize_run_id is not null then
    if tg_op = 'UPDATE'
       and old.show_id = new.show_id
       and old.finalize_run_id = new.finalize_run_id
       and old.report_name = new.report_name
       and old.artifact_key = public.closeout_artifact_identity(new.report_name, new.metadata)
       and old.scope_key = public.closeout_artifact_scope_key(
         old.show_id, old.report_name, old.section_ids, old.metadata
       ) then
      new.scope_key := old.scope_key;
      new.section_ids := old.section_ids;
      new.artifact_key := old.artifact_key;
      new.metadata := new.metadata || jsonb_build_object(
        'scope_key', old.scope_key,
        'section_ids', to_jsonb(old.section_ids),
        'run_scope_key', old.metadata ->> 'run_scope_key'
      );
    else
      select * into v_scope from public.resolve_closeout_artifact_scope(
        new.show_id, new.finalize_run_id, new.report_name, new.metadata
      );
      if not coalesce(v_scope.is_repairable, false) then
        raise exception 'Cannot derive canonical closeout artifact scope: %',
          coalesce(v_scope.failure_reason, 'unknown_scope');
      end if;
      new.scope_key := v_scope.scope_key;
      new.section_ids := v_scope.section_ids;
      new.metadata := v_scope.metadata;
      new.artifact_key := v_scope.artifact_key;
    end if;
  end if;
  if new.finalize_run_id is not null and new.id is not null then
    new.storage_bucket := coalesce(nullif(new.storage_bucket, ''), 'show-files');
    new.storage_path := coalesce(nullif(new.storage_path, ''), format(
      'shows/%s/reports/versions/%s/artifacts/%s/generation-%s/report.pdf',
      new.show_id, new.finalize_run_id, new.id, new.generation
    ));
  end if;
  return new;
end;
$function$;

create or replace function public.queue_opted_in_sweepstakes_json_export()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_metadata jsonb;
  v_scope_key text;
begin
  if new.report_name <> 'sweepstakes_report'::public.report_type
     or not exists (
       select 1 from public.sweepstakes_json_export_opt_ins opt_in
       where opt_in.enabled
         and lower(btrim(opt_in.club_name)) = lower(btrim(coalesce(new.metadata ->> 'club_name', '')))
         and (
           btrim(opt_in.breed_name) = '*'
           or lower(btrim(opt_in.breed_name)) = lower(btrim(coalesce(new.metadata ->> 'breed_name', '')))
         )
     ) then
    return new;
  end if;

  v_metadata := new.metadata || jsonb_build_object('delivery_type', 'club');
  v_scope_key := public.closeout_artifact_scope_key(
    new.show_id, 'sweepstakes_json_export'::public.report_type,
    new.section_ids, v_metadata
  );
  v_metadata := v_metadata || jsonb_build_object('scope_key', v_scope_key);

  insert into public.show_report_artifacts (
    show_id, finalize_run_id, report_name, artifact_status, metadata,
    is_current, scope_key, section_ids
  ) values (
    new.show_id, new.finalize_run_id, 'sweepstakes_json_export', 'queued',
    v_metadata, new.is_current, v_scope_key, new.section_ids
  );
  return new;
end;
$function$;

drop trigger if exists queue_opted_in_sweepstakes_json_export on public.show_report_artifacts;
create trigger queue_opted_in_sweepstakes_json_export
after insert on public.show_report_artifacts
for each row execute function public.queue_opted_in_sweepstakes_json_export();

update storage.buckets
set allowed_mime_types = array['application/pdf', 'text/csv', 'application/json']
where id = 'show-files';

-- Initial administrator-approved club-wide opt-ins.
insert into public.sweepstakes_json_export_opt_ins (club_name, breed_name, enabled)
values
  ('American Dutch Rabbit Club', '*', true),
  ('American Satin Rabbit Breeders Association', '*', true),
  ('American English Spot Rabbit Club', '*', true),
  ('American Tan Rabbit Specialty Club', '*', true),
  ('Florida White Rabbit Club', '*', true),
  ('Giant Chinchilla Rabbit Association', '*', true),
  ('National Rex Rabbit Club', '*', true),
  ('National Silver Fox Rabbit Club', '*', true),
  ('Lop Rabbit Club of America', '*', true),
  ('Mid Atlantic Lop Club', '*', true),
  ('Ohio State Dutch Rabbit Club', '*', true)
on conflict (club_name, breed_name) do update
set enabled = excluded.enabled,
    updated_at = now();
