-- A transition applies on its effective date, using the section's judging date.
-- No catalog names, historical entries, awards, or production rules are seeded.
begin;
create or replace function public.catalog_recognition_key(p_name text)
returns text language sql immutable security invoker set search_path = '' as $$
 select lower(btrim(regexp_replace(regexp_replace(coalesce(p_name,''),
   '\s*\(\s*COD\s*\)|\mCOD\M', '', 'gi'), '\s+', ' ', 'g')));
$$;

create table public.catalog_recognition_history (
 id uuid primary key default gen_random_uuid(),
 species text not null check (species in ('rabbit','cavy')),
 breed_name text not null check (btrim(breed_name) <> ''),
 variety_name text not null default '',
 breed_key text generated always as (public.catalog_recognition_key(breed_name)) stored,
 variety_key text generated always as (public.catalog_recognition_key(variety_name)) stored,
 status text not null check (status in ('cod','recognized','retired')),
 effective_date date not null,
 source_note text not null default '',
 created_at timestamptz not null default now(),
 created_by uuid default auth.uid(),
 unique(species,breed_key,variety_key,effective_date)
);
alter table public.catalog_recognition_history enable row level security;
revoke all on public.catalog_recognition_history from public,anon,authenticated;
grant select on public.catalog_recognition_history to authenticated, service_role;
grant insert, delete on public.catalog_recognition_history to authenticated, service_role;
create policy recognition_read on public.catalog_recognition_history for select to authenticated using (true);
create policy recognition_add on public.catalog_recognition_history for insert to authenticated
 with check ((select public.is_super_admin()) and created_by = (select auth.uid()));
create policy recognition_remove on public.catalog_recognition_history for delete to authenticated
 using ((select public.is_super_admin()) and effective_date > current_date);

create table public.catalog_recognition_audit (
 id bigint generated always as identity primary key,
 action text not null,
 event jsonb not null,
 actor_id uuid default auth.uid(),
 changed_at timestamptz not null default now()
);
alter table public.catalog_recognition_audit enable row level security;
revoke all on public.catalog_recognition_audit from public,anon,authenticated;
revoke all on sequence public.catalog_recognition_audit_id_seq from public,anon,authenticated;
grant select on public.catalog_recognition_audit to authenticated, service_role;
create policy recognition_audit_read on public.catalog_recognition_audit for select to authenticated
 using ((select public.is_super_admin()));

create or replace function public.catalog_recognition_status(
 p_species text, p_breed text, p_variety text, p_judging_date date)
returns text language plpgsql stable security invoker set search_path = '' as $$
declare b text; v text; has_timeline boolean;
begin
 select exists(select 1 from public.catalog_recognition_history h
  where h.species=lower(p_species) and h.breed_key=public.catalog_recognition_key(p_breed)
    and h.variety_key in ('',public.catalog_recognition_key(p_variety))) into has_timeline;
 if p_judging_date is null and has_timeline then return 'unrecognized'; end if;
 select h.status into b from public.catalog_recognition_history h
  where h.species=lower(p_species) and h.breed_key=public.catalog_recognition_key(p_breed)
    and h.variety_key='' and h.effective_date <= p_judging_date
  order by h.effective_date desc limit 1;
 select h.status into v from public.catalog_recognition_history h
  where h.species=lower(p_species) and h.breed_key=public.catalog_recognition_key(p_breed)
    and h.variety_key=public.catalog_recognition_key(p_variety) and h.variety_key<>''
    and h.effective_date <= p_judging_date order by h.effective_date desc limit 1;
 -- Preserve legacy behavior before a subject's first transition. This also
 -- preserves old '(COD)' entries when recognition is scheduled in the future.
 b := coalesce(b, case when public.is_cod_entry(p_breed,'') then 'cod' else 'recognized' end);
 v := coalesce(v, case when public.is_cod_entry('',p_variety) then 'cod' else 'recognized' end);
 if 'retired' in (b,v) then return 'retired'; end if;
 if 'cod' in (b,v) then return 'cod'; end if;
 return 'recognized';
end $$;

create or replace function public.entry_recognition_context(p_entry_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
 select jsonb_build_object('recognition_status', public.catalog_recognition_status(
   case when lower(coalesce(e.species::text,''))='cavy' or lower(e.sex) in ('boar','sow') then 'cavy' else 'rabbit' end,
   e.breed,e.variety,coalesce(s.judging_date,sh.start_date)),
   'recognition_judging_date',coalesce(s.judging_date,sh.start_date))
 from public.entries e join public.shows sh on sh.id=e.show_id
 left join public.show_sections s on s.id=e.section_id and s.show_id=e.show_id
 where e.id=p_entry_id;
$$;
create or replace function public.entry_recognition_status(p_entry_id uuid)
returns text language sql stable security invoker set search_path = '' as $$
 select coalesce(public.entry_recognition_context(p_entry_id)->>'recognition_status','unrecognized');
$$;

-- Audit writes use a private trigger function; browser roles cannot write logs.
create schema if not exists catalog_recognition_private;
revoke all on schema catalog_recognition_private from public, anon, authenticated;
create or replace function catalog_recognition_private.audit_transition()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.catalog_recognition_audit(action,event,actor_id)
 values (TG_OP,case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end,auth.uid());
 return null;
end $$;
revoke all on function catalog_recognition_private.audit_transition() from public, anon, authenticated;
create trigger recognition_audit after insert or delete on public.catalog_recognition_history
 for each row execute function catalog_recognition_private.audit_transition();

create or replace function catalog_recognition_private.protect_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if TG_OP='DELETE' then
   if old.effective_date <= current_date then
     raise exception 'Effective status history cannot be deleted. Add a new dated transition.' using errcode='23514';
   end if;
   new := old;
 end if;
 -- Prevent backdated status changes from silently rewriting judged results.
 if exists(select 1 from public.entries e join public.shows sh on sh.id=e.show_id
   left join public.show_sections s on s.id=e.section_id
   where public.catalog_recognition_key(e.breed)=public.catalog_recognition_key(new.breed_name)
     and lower(coalesce(e.species::text,'rabbit'))=new.species
     and (new.variety_name='' or public.catalog_recognition_key(e.variety)=public.catalog_recognition_key(new.variety_name))
     and coalesce(s.judging_date,sh.start_date)>=new.effective_date
     and (e.result_entered_at is not null or nullif(e.placement,'') is not null
       or exists(select 1 from public.entry_awards a where a.entry_id=e.id))) then
   raise exception 'This effective date overlaps judged entries. Historical results require a separate review.' using errcode='23514';
 end if;
 if TG_OP='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function catalog_recognition_private.protect_history() from public, anon, authenticated;
create trigger recognition_protect before insert or delete on public.catalog_recognition_history
 for each row execute function catalog_recognition_private.protect_history();

-- Retired entries remain readable/editable historically, but cannot be newly
-- submitted for a section where the breed/variety is retired.
create or replace function public.validate_entry_recognition()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare d date; st text;
begin
 if TG_OP='UPDATE' and (new.breed,new.variety,new.species,new.section_id,new.show_id)
   is not distinct from (old.breed,old.variety,old.species,old.section_id,old.show_id) then return new; end if;
 select coalesce(s.judging_date,sh.start_date) into d from public.shows sh
 left join public.show_sections s on s.show_id=sh.id and s.id=new.section_id where sh.id=new.show_id;
 st := public.catalog_recognition_status(coalesce(new.species::text,'rabbit'),new.breed,new.variety,d);
 if st in ('retired','unrecognized') then
  raise exception 'This breed or variety is not eligible on the section judging date.' using errcode='23514';
 end if;
 return new;
end $$;
create trigger validate_entry_recognition before insert or update of breed,variety,species,section_id,show_id on public.entries
 for each row execute function public.validate_entry_recognition();

-- Existing SQL callers keep their scopes and authorization; only their COD
-- classification is replaced with entry-specific dated recognition.
do $$
declare f record; body text;
begin
 for f in select p.oid,n.nspname,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prokind='f' and n.nspname in ('public','show_awards_private')
   and p.proname in ('validate_cod_awards','show_results_readiness_scoped',
    'calculate_sweepstakes_for_breed_baseline','calculate_sweepstakes_for_breed_legacy',
    'calculate_sweepstakes_for_breed_portal_class_schedule') loop
  body := pg_get_functiondef(f.oid);
  body := replace(body,'public.is_cod_entry(v_entry.breed, v_entry.variety)',
    '(public.entry_recognition_status(v_entry.id) <> ''recognized'')');
  body := replace(body,'public.is_cod_entry(e.breed, e.variety)',
    '(public.entry_recognition_status(e.id) <> ''recognized'')');
  body := replace(body,'public.is_cod_entry(entry.breed, entry.variety)',
    '(public.entry_recognition_status(entry.id) <> ''recognized'')');
  body := replace(body,'public.is_cod_entry(breed_key, variety_key)',
    '(public.entry_recognition_status(entry_id) <> ''recognized'')');
  body := replace(body,'public.is_cod_entry(breed_name, variety_name)',
    '(public.entry_recognition_status(entry_id) <> ''recognized'')');
  execute body;
 end loop;
end $$;

-- Cavy award-based sweepstakes and generic award points use the same date.
do $$
declare body text;
begin
 select pg_get_functiondef('public.calculate_cavy_sweepstakes_for_section_baseline(uuid,text,text)'::regprocedure) into body;
 body := replace(body,'and coalesce(e.is_shown, true)',
   'and coalesce(e.is_shown, true) and public.entry_recognition_status(e.id) = ''recognized''');
 execute body;
 select pg_get_functiondef('public.generate_show_award_points_entries(uuid,uuid)'::regprocedure) into body;
 body := replace(body,'case when scratched_at is not null or not is_shown or is_disqualified',
   'case when public.entry_recognition_status(entry_id) <> ''recognized'' or scratched_at is not null or not is_shown or is_disqualified');
 body := replace(body,'scratched_at is null and is_shown and not is_disqualified,',
   'public.entry_recognition_status(entry_id) = ''recognized'' and scratched_at is null and is_shown and not is_disqualified,');
 body := replace(body,'when scratched_at is not null then ''Scratched''',
   'when public.entry_recognition_status(entry_id) <> ''recognized'' then ''Recognition status ineligible'' when scratched_at is not null then ''Scratched''');
 execute body;
end $$;

-- Retired status does not retain the BOV/BOSV exception allowed for COD.
create or replace function public.validate_retired_awards()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare eid uuid; st text;
begin
 if TG_TABLE_NAME='entry_awards' then eid := new.entry_id; else eid := new.id; end if;
 st := public.entry_recognition_status(eid);
 if st in ('retired','unrecognized') and (
   exists(select 1 from public.entry_awards where entry_id=eid)
   or exists(select 1 from public.entries where id=eid and nullif(btrim(special_awards),'') is not null)) then
  raise exception 'Retired or undated entries cannot receive awards or legs.' using errcode='23514';
 end if;
 return null;
end $$;
create constraint trigger recognition_entry_awards after insert or update on public.entries
 deferrable initially deferred for each row execute function public.validate_retired_awards();
create constraint trigger recognition_awards after insert or update on public.entry_awards
 deferrable initially deferred for each row execute function public.validate_retired_awards();

-- A JSON companion keeps the established typed result RPC backward compatible.
-- Authorization remains in report_results_entry_rows_page; the wrapper is invoker.
create or replace function public.report_results_entry_rows_dated_page(
 p_show_id uuid,p_section_id uuid default null,p_show_letter text default null,
 p_breed text default null,p_entry_ids uuid[] default null,p_after_entry_id uuid default null,
 p_page_size integer default 1000)
returns setof jsonb language sql stable security invoker set search_path = '' as $$
 select to_jsonb(r) || coalesce(public.entry_recognition_context(r.entry_id),'{}'::jsonb)
 from public.report_results_entry_rows_page(p_show_id,p_section_id,p_show_letter,p_breed,p_entry_ids,p_after_entry_id,p_page_size) r;
$$;
do $$
declare body text;
begin
 select pg_get_functiondef('public.get_judging_entry_rows_page(uuid,uuid,text,text,uuid[],uuid,integer)'::regprocedure) into body;
 body := replace(body,'select to_jsonb(r) || jsonb_build_object(',
   'select to_jsonb(r) || coalesce(public.entry_recognition_context(r.entry_id),''{}''::jsonb) || jsonb_build_object(');
 execute body;
 -- Include catalog changes in the snapshot revision so a long-lived worker
 -- never reuses eligibility resolved under an earlier timeline.
 select pg_get_functiondef('public.get_report_result_revision_scoped(uuid,uuid[])'::regprocedure) into body;
 body := replace(body,'end;', 'end || '':recognition:'' || coalesce((select max(id)::text from public.catalog_recognition_audit),''0'');');
 execute body;
end $$;

revoke all on function public.catalog_recognition_key(text),
 public.catalog_recognition_status(text,text,text,date),public.entry_recognition_context(uuid),
 public.entry_recognition_status(uuid),public.validate_entry_recognition(),public.validate_retired_awards(),
 public.report_results_entry_rows_dated_page(uuid,uuid,text,text,uuid[],uuid,integer) from public,anon;
grant execute on function public.catalog_recognition_key(text),
 public.catalog_recognition_status(text,text,text,date),public.entry_recognition_context(uuid),
 public.entry_recognition_status(uuid),public.validate_entry_recognition(),public.validate_retired_awards(),
 public.report_results_entry_rows_dated_page(uuid,uuid,text,text,uuid[],uuid,integer) to authenticated,service_role;
create or replace function public.report_results_entry_rows_dated(p_show_id uuid,p_section_id uuid default null,p_show_letter text default null)
returns setof jsonb language sql stable security invoker set search_path = '' as $$
 select to_jsonb(r) || coalesce(public.entry_recognition_context(r.entry_id),'{}'::jsonb)
 from public.report_results_entry_rows(p_show_id,p_section_id,p_show_letter) r;
$$;
create or replace function public.report_results_entry_rows_for_breed_detail_dated(p_show_id uuid,p_breed_name text,p_scope text,p_show_letter text default null)
returns setof jsonb language sql stable security invoker set search_path = '' as $$
 select to_jsonb(r) || coalesce(public.entry_recognition_context(r.entry_id),'{}'::jsonb)
 from public.report_results_entry_rows_for_breed_detail(p_show_id,p_breed_name,p_scope,p_show_letter) r;
$$;
revoke all on function public.report_results_entry_rows_dated(uuid,uuid,text), public.report_results_entry_rows_for_breed_detail_dated(uuid,text,text,text) from public,anon;
grant execute on function public.report_results_entry_rows_dated(uuid,uuid,text), public.report_results_entry_rows_for_breed_detail_dated(uuid,text,text,text) to authenticated,service_role;
notify pgrst, 'reload schema';

commit;
