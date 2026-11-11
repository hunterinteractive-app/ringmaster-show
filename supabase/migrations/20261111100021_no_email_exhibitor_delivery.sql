-- Only unowned, show-created manual exhibitors can omit email. Account-backed
-- exhibitors still retain the existing email requirement.
alter table public.exhibitors drop constraint exhibitors_email_required_except_name_only_manual_shows;
alter table public.exhibitors add constraint exhibitors_email_required_except_name_only_manual_shows
check (email is not null or (is_local_only and created_for_show_id is not null and owner_user_id is null)
  or (is_local_only and created_for_show_id='373d1b96-45bb-4f29-a630-96279ed0e91e'::uuid));

create policy staff_insert_no_email_exhibitor on public.exhibitors for insert to authenticated
with check (owner_user_id is null and is_local_only and
  nullif(trim(email),'') is null and created_for_show_id is not null and
  public.user_can_manage_show(created_for_show_id, (select auth.uid())));

-- No-email exhibitors already use nullable contact fields and unowned local records.
-- Track delivery against the precise artifact revision, not merely an exhibitor.
create table public.report_manual_deliveries (
  artifact_id uuid not null references public.show_report_artifacts(id) on delete cascade,
  generation integer not null,
  show_id uuid not null references public.shows(id) on delete cascade,
  method text not null check (method in ('mailed','handed_out')),
  recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default now(),
  primary key(artifact_id,generation)
);
alter table public.report_manual_deliveries enable row level security;
revoke all on public.report_manual_deliveries from public,anon,authenticated;
grant select on public.report_manual_deliveries to authenticated;
grant all on public.report_manual_deliveries to service_role;
create policy staff_read_manual_deliveries on public.report_manual_deliveries
for select to authenticated using (public.user_can_email_reports(show_id));
create index manual_delivery_show on public.report_manual_deliveries(show_id);

create schema if not exists report_delivery_private;
revoke all on schema report_delivery_private from public,anon;
grant usage on schema report_delivery_private to authenticated,service_role;

create function report_delivery_private.mark_delivered(p_show_id uuid,p_artifacts jsonb,p_method text)
returns void language plpgsql security definer set search_path='' as $$
declare item jsonb; a public.show_report_artifacts;
begin
 if auth.uid() is null or not public.user_can_email_reports(p_show_id) then
   raise exception 'Show staff access required.' using errcode='42501';
 end if;
 if p_method not in ('mailed','handed_out','pending') or p_method is null
    or jsonb_typeof(p_artifacts) is distinct from 'array' or jsonb_array_length(p_artifacts)=0 then
   raise exception 'Choose reports and a delivery method.' using errcode='22023';
 end if;
 for item in select value from jsonb_array_elements(p_artifacts) loop
   select * into a from public.show_report_artifacts where id=(item->>'id')::uuid and show_id=p_show_id
     and is_current and generation=(item->>'generation')::int and artifact_status::text='generated'
     and report_name in ('exhibitor_report','legs','checkin_sheet') for share;
   if a.id is null then raise exception 'Reports changed. Refresh before recording delivery.' using errcode='22023'; end if;
   if p_method='pending' then
     delete from public.report_manual_deliveries where artifact_id=a.id and generation=a.generation;
   else
     insert into public.report_manual_deliveries(artifact_id,generation,show_id,method,recorded_by)
     values(a.id,a.generation,p_show_id,p_method,auth.uid())
     on conflict(artifact_id,generation) do update set method=excluded.method,recorded_by=excluded.recorded_by,recorded_at=now();
   end if;
 end loop;
end $$;
revoke all on function report_delivery_private.mark_delivered(uuid,jsonb,text) from public,anon;
grant execute on function report_delivery_private.mark_delivered(uuid,jsonb,text) to authenticated;
create function public.mark_report_manual_delivery(p_show_id uuid,p_artifacts jsonb,p_method text)
returns void language sql security invoker set search_path='' as $$
 select report_delivery_private.mark_delivered(p_show_id,p_artifacts,p_method);
$$;
revoke all on function public.mark_report_manual_delivery(uuid,jsonb,text) from public,anon;
grant execute on function public.mark_report_manual_delivery(uuid,jsonb,text) to authenticated;

-- Keep the existing all-exhibitor pack allowlist separate from staff no-email packs.
alter table public.exhibitor_print_packs add column manual_delivery boolean not null default false;
alter table public.exhibitor_print_packs add column section_id uuid references public.show_sections(id);
alter table public.exhibitor_print_packs add column report_family text not null default 'results'
  check(report_family in ('results','checkin'));
drop index public.one_current_exhibitor_print_pack;
create unique index one_current_exhibitor_print_pack on public.exhibitor_print_packs(show_id) where is_current and not manual_delivery;
create unique index one_current_manual_print_pack on public.exhibitor_print_packs(show_id,coalesce(section_id,'00000000-0000-0000-0000-000000000000'::uuid),report_family) where is_current and manual_delivery;
alter policy print_pack_select on public.exhibitor_print_packs using (
 (not manual_delivery and public.can_access_exhibitor_print_pack(show_id)) or
 (manual_delivery and public.user_can_email_reports(show_id)));

create or replace function public.can_download_exhibitor_print_pack(p_path text)
returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and exists (select 1 from public.exhibitor_print_packs p
   where p.storage_path=p_path and p.is_current and p.artifact_status='generated');
$$;
-- RLS on exhibitor_print_packs enforces the appropriate access rule above.

create function report_delivery_private.sources(p_show_id uuid,p_section_id uuid,p_family text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_agg(jsonb_build_object('id',a.id,'generation',a.generation,
   'storage_bucket',a.storage_bucket,'storage_path',a.storage_path,'sha256',a.file_hash_sha256,
   'artifact_status',a.artifact_status,'report_name',a.report_name,'exhibitor_id',e.id,
   'label',concat_ws(' - ',coalesce(nullif(e.showing_name,''),e.display_name,e.first_name||' '||e.last_name),a.report_name))
   order by lower(coalesce(e.last_name,e.showing_name,e.display_name,'')), e.id,
     case when a.report_name='legs' then 1 else 0 end,a.scope_key,a.id)
 from public.show_report_artifacts a join public.exhibitors e on e.id::text=a.metadata->>'exhibitor_id'
 where a.show_id=p_show_id and a.is_current and nullif(trim(e.email),'') is null
   and (p_section_id is null or p_section_id=any(a.section_ids) or a.metadata->>'section_id'=p_section_id::text)
   and ((p_family='results' and a.report_name in ('exhibitor_report','legs')) or (p_family='checkin' and a.report_name='checkin_sheet'));
$$;
revoke all on function report_delivery_private.sources(uuid,uuid,text) from public,anon,authenticated;
grant execute on function report_delivery_private.sources(uuid,uuid,text) to service_role;

create function report_delivery_private.queue_pack(p_show_id uuid,p_section_id uuid,p_family text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_sources jsonb;
begin
 if auth.uid() is null or not public.user_can_email_reports(p_show_id) then
   raise exception 'Show staff access required.' using errcode='42501';
 end if;
 if p_family not in ('results','checkin') or p_family is null or
   (p_section_id is not null and not exists(select 1 from public.show_sections where id=p_section_id and show_id=p_show_id)) then
   raise exception 'Invalid report scope.' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('manual-print:'||p_show_id::text,0));
 v_sources:=report_delivery_private.sources(p_show_id,p_section_id,p_family);
 if v_sources is null then raise exception 'No no-email reports are available. Generate reports first.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_array_elements(v_sources) s where s->>'artifact_status'<>'generated' or nullif(s->>'storage_path','') is null) then
   raise exception 'Finish generating these reports before printing.' using errcode='22023';
 end if;
 select id into v_id from public.exhibitor_print_packs where show_id=p_show_id and manual_delivery
   and section_id is not distinct from p_section_id and report_family=p_family and is_current
   and sources=v_sources and artifact_status in ('queued','running','generated');
 if v_id is not null then return v_id; end if;
 update public.exhibitor_print_packs set is_current=false where show_id=p_show_id and manual_delivery
   and section_id is not distinct from p_section_id and report_family=p_family and is_current;
 v_id:=gen_random_uuid();
 insert into public.exhibitor_print_packs(id,show_id,requested_by,sources,storage_path,manual_delivery,section_id,report_family,file_name)
 values(v_id,p_show_id,auth.uid(),v_sources,p_show_id::text||'/'||v_id::text||'/report.pdf',true,p_section_id,p_family,'print-mail-'||p_family||'.pdf');
 return v_id;
end $$;
revoke all on function report_delivery_private.queue_pack(uuid,uuid,text) from public,anon;
grant execute on function report_delivery_private.queue_pack(uuid,uuid,text) to authenticated;
create function public.queue_manual_report_print_pack(p_show_id uuid,p_section_id uuid default null,p_family text default 'results')
returns uuid language sql security invoker set search_path='' as $$
 select report_delivery_private.queue_pack(p_show_id,p_section_id,p_family);
$$;
revoke all on function public.queue_manual_report_print_pack(uuid,uuid,text) from public,anon;
grant execute on function public.queue_manual_report_print_pack(uuid,uuid,text) to authenticated;

-- Worker-only manifest read rechecks staff authorization and current contact data.
create function public.manual_print_pack_current_sources(p_pack_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare p public.exhibitor_print_packs;
begin
 select * into p from public.exhibitor_print_packs where id=p_pack_id and manual_delivery and is_current;
 if p.id is null or not public.user_can_email_reports(p.show_id,p.requested_by) then
   raise exception 'Print pack access was revoked.' using errcode='42501';
 end if;
 return coalesce(report_delivery_private.sources(p.show_id,p.section_id,p.report_family),'[]'::jsonb);
end $$;
revoke all on function public.manual_print_pack_current_sources(uuid) from public,anon,authenticated;
grant execute on function public.manual_print_pack_current_sources(uuid) to service_role;

create or replace function public.queue_exhibitor_print_pack(p_show_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_sources jsonb;
begin
  if auth.uid() is null or not public.can_access_exhibitor_print_pack(p_show_id) then
    raise exception 'This report is restricted to selected accounts.' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('exhibitor-print-pack:' || p_show_id::text,0));
  select id into v_id from public.exhibitor_print_packs
    where show_id = p_show_id and not manual_delivery and is_current and artifact_status in ('queued','running');
  if v_id is not null then return v_id; end if;
  if exists (select 1 from public.show_report_artifacts a
      where a.show_id = p_show_id and a.is_current
        and a.report_name in ('exhibitor_report','legs')
        and (a.artifact_status::text <> 'generated' or nullif(a.storage_path,'') is null)) then
    raise exception 'Finish generating all exhibitor reports and legs in Step 5 before creating the print pack.';
  end if;
  select jsonb_agg(jsonb_build_object(
    'id',a.id,'generation',a.generation,'storage_bucket',a.storage_bucket,
    'storage_path',a.storage_path,'sha256',a.file_hash_sha256,
    'report_name',a.report_name,'exhibitor_id',a.metadata->>'exhibitor_id',
    'label',concat_ws(' - ',coalesce(nullif(e.display_name,''),a.metadata->>'exhibitor_name'),
      case when a.report_name = 'legs' then 'Legs' else 'Exhibitor Report' end,
      nullif(a.metadata->>'species',''))
  ) order by lower(coalesce(nullif(e.last_name,''),e.display_name,a.metadata->>'exhibitor_name','')),
    lower(coalesce(e.first_name,'')),a.metadata->>'exhibitor_id',
    case when a.report_name='exhibitor_report' then 0 else 1 end,
    a.metadata->>'species',a.scope_key,a.id)
  into v_sources from public.show_report_artifacts a
  left join public.exhibitors e on e.id::text = a.metadata->>'exhibitor_id'
  where a.show_id = p_show_id and a.is_current
    and a.report_name in ('exhibitor_report','legs');
  if v_sources is null then
    raise exception 'Generate exhibitor reports and legs in Step 5 first.';
  end if;
  update public.exhibitor_print_packs set is_current=false
    where show_id=p_show_id and not manual_delivery and is_current;
  v_id := gen_random_uuid();
  insert into public.exhibitor_print_packs(id,show_id,requested_by,sources,storage_path)
  values (v_id,p_show_id,auth.uid(),v_sources,p_show_id::text || '/' || v_id::text || '/report.pdf');
  return v_id;
end;
$$;
