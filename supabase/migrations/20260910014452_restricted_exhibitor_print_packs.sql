-- Separate from ordinary closeout artifacts: these packs must never join
-- delivery jobs, general requeues, or the broadly readable show-files bucket.
create table public.exhibitor_print_pack_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.exhibitor_print_pack_accounts enable row level security;
revoke all on public.exhibitor_print_pack_accounts from anon, authenticated;
grant select on public.exhibitor_print_pack_accounts to authenticated;
grant all on public.exhibitor_print_pack_accounts to service_role;
create policy print_pack_account_self on public.exhibitor_print_pack_accounts
  for select to authenticated using (user_id = (select auth.uid()));

create function public.can_access_exhibitor_print_pack(p_show_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (select 1 from public.exhibitor_print_pack_accounts a
                 where a.user_id = (select auth.uid()))
    and (public.user_can_manage_show_settings(p_show_id)
         or public.user_can_email_reports(p_show_id));
$$;
revoke all on function public.can_access_exhibitor_print_pack(uuid) from public, anon;
grant execute on function public.can_access_exhibitor_print_pack(uuid) to authenticated, service_role;

create table public.exhibitor_print_packs (
  id uuid primary key default gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  artifact_status text not null default 'queued'
    check (artifact_status in ('queued','running','generated','failed')),
  is_current boolean not null default true,
  sources jsonb not null check (jsonb_typeof(sources) = 'array'),
  storage_bucket text not null default 'exhibitor-print-packs'
    check (storage_bucket = 'exhibitor-print-packs'),
  storage_path text not null unique,
  file_name text not null default 'exhibitor-reports-and-legs.pdf',
  file_size_bytes bigint,
  page_count integer,
  error_message text,
  created_at timestamptz not null default now(),
  generated_at timestamptz,
  claimed_at timestamptz,
  claim_token uuid,
  attempt_count integer not null default 0
);
create unique index one_current_exhibitor_print_pack
  on public.exhibitor_print_packs(show_id) where is_current;
create index pending_exhibitor_print_packs on public.exhibitor_print_packs(created_at)
  where is_current and artifact_status in ('queued','running');
alter table public.exhibitor_print_packs enable row level security;
revoke all on public.exhibitor_print_packs from anon, authenticated;
grant select on public.exhibitor_print_packs to authenticated;
grant all on public.exhibitor_print_packs to service_role;
create policy print_pack_select on public.exhibitor_print_packs
  for select to authenticated using (public.can_access_exhibitor_print_pack(show_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('exhibitor-print-packs','exhibitor-print-packs',false,1073741824,array['application/pdf']);
create function public.can_download_exhibitor_print_pack(p_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and exists (
    select 1 from public.exhibitor_print_packs p
    where p.storage_path=p_path and p.is_current and p.artifact_status='generated'
      and public.can_access_exhibitor_print_pack(p.show_id)
  );
$$;
revoke all on function public.can_download_exhibitor_print_pack(text) from public;
grant execute on function public.can_download_exhibitor_print_pack(text) to anon, authenticated, service_role;
-- RESTRICTIVE is essential: existing permissive policies allow authenticated
-- reads/uploads regardless of bucket. Never allow client writes into this one.
create policy private_print_pack_read_guard on storage.objects as restrictive
  for select to public using (
    bucket_id <> 'exhibitor-print-packs' or public.can_download_exhibitor_print_pack(name)
  );
create policy private_print_pack_insert_guard on storage.objects as restrictive
  for insert to public with check (bucket_id <> 'exhibitor-print-packs');
create policy private_print_pack_update_guard on storage.objects as restrictive
  for update to public using (bucket_id <> 'exhibitor-print-packs')
  with check (bucket_id <> 'exhibitor-print-packs');
create policy private_print_pack_delete_guard on storage.objects as restrictive
  for delete to public using (bucket_id <> 'exhibitor-print-packs');

create function public.queue_exhibitor_print_pack(p_show_id uuid)
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
    where show_id = p_show_id and is_current and artifact_status in ('queued','running');
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
    where show_id=p_show_id and is_current;
  v_id := gen_random_uuid();
  insert into public.exhibitor_print_packs(id,show_id,requested_by,sources,storage_path)
  values (v_id,p_show_id,auth.uid(),v_sources,p_show_id::text || '/' || v_id::text || '/report.pdf');
  return v_id;
end;
$$;
revoke all on function public.queue_exhibitor_print_pack(uuid) from public, anon;
grant execute on function public.queue_exhibitor_print_pack(uuid) to authenticated;

create function public.claim_exhibitor_print_pack()
returns setof public.exhibitor_print_packs
language plpgsql security invoker set search_path = '' as $$
begin
  update public.exhibitor_print_packs set artifact_status='failed',
    error_message='Generation timed out. Generate the print pack again.'
  where is_current and artifact_status='running'
    and claimed_at < now()-interval '15 minutes' and attempt_count >= 3;
  return query
  update public.exhibitor_print_packs p set artifact_status='running',
    claimed_at=now(),claim_token=gen_random_uuid(),attempt_count=attempt_count+1
  where p.id=(select q.id from public.exhibitor_print_packs q
    where q.is_current and (q.artifact_status='queued' or
      (q.artifact_status='running' and q.claimed_at < now()-interval '15 minutes'))
    order by q.created_at for update skip locked limit 1)
  returning p.*;
end;
$$;
revoke all on function public.claim_exhibitor_print_pack() from public, anon, authenticated;
grant execute on function public.claim_exhibitor_print_pack() to service_role;

insert into public.exhibitor_print_pack_accounts(user_id) values
  ('3e8dddf9-3a17-4ebb-aeab-9b51d31e7871'),
  ('cad4eb5f-239a-4990-b372-e8a43e3faee8');
