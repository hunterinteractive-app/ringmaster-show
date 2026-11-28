-- The Closeout state-club directory already exists in production. Include
-- its schema for environments that have only the versioned migrations.
do $directory$
begin
  if to_regclass('public.state_club_report_contacts') is null then
    create table public.state_club_report_contacts (
      id uuid primary key default gen_random_uuid(),
      club_name text not null,
      species text not null default 'combined' check (species in ('combined','rabbit','cavy')),
      email text not null,
      is_active boolean not null default true,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique (club_name,species,email)
    );
    alter table public.state_club_report_contacts enable row level security;
    create policy state_club_report_contacts_select_authenticated on public.state_club_report_contacts
      for select to authenticated using (true);
    create policy state_club_report_contacts_write_super_admin on public.state_club_report_contacts
      for all to authenticated
      using (exists (select 1 from public.role_assignments where user_id=auth.uid() and role='super_admin'))
      with check (exists (select 1 from public.role_assignments where user_id=auth.uid() and role='super_admin'));
  end if;
end;
$directory$;

-- Default report email deduplication stays artifact-based. An explicitly
-- confirmed sanction correction can deliver a new generation of that artifact.
alter table public.show_email_deliveries add column if not exists artifact_generation integer;

create function private.sanction_club_report_targets(p_show_id uuid,p_changes jsonb)
returns table(sanction_id uuid,section_label text,club_name text,recipient text,
  finalize_run_id uuid,report_name public.report_type,scope_key text,section_ids uuid[],
  metadata jsonb,artifact_key text)
language sql stable set search_path='' as $$
  select s.id,coalesce(nullif(btrim(sec.display_name),''),initcap(sec.kind::text)||' '||sec.letter),
    btrim(s.club_name),destination.email,f.id,report.name,scope.scope_key,
    scope.section_ids,scope.metadata,scope.artifact_key
  from jsonb_each_text(p_changes) as changed(id,number)
  join public.show_sanctions s on s.id::text=changed.id and s.show_id=p_show_id
    and btrim(s.sanction_number)=changed.number
  join public.show_sections sec on sec.id=s.section_id and sec.show_id=s.show_id and sec.is_enabled
  join public.shows sh on sh.id=s.show_id and not coalesce(sh.email_sending_disabled,false)
    and not coalesce(sh.is_demo,false)
  join lateral (
    select r.id,r.scope_label,r.section_ids from public.show_finalize_runs r
    where r.show_id=p_show_id and r.run_status='completed' and sec.id=any(r.section_ids)
    order by r.created_at desc,r.id desc limit 1
  ) f on true
  cross join lateral (select upper(btrim(s.sanctioning_body)) as body) kind
  join lateral (
    select distinct lower(e.species::text) as name from public.entries e
    where e.show_id=p_show_id and e.section_id=sec.id and e.is_shown and e.scratched_at is null
      and (kind.body='STATE CLUB'
        or (lower(btrim(s.breed_name))='cavy' and e.species::text='cavy')
        or (lower(btrim(s.breed_name))<>'cavy' and lower(btrim(e.breed))=lower(btrim(s.breed_name))
          and (e.species::text='rabbit' or not exists (
            select 1 from public.breeds b where b.is_active and b.species::text='rabbit'
              and lower(btrim(b.name))=lower(btrim(s.breed_name))
          ))))
      and lower(e.species::text) in ('rabbit','cavy')
  ) species on true
  left join lateral (
    select btrim(c.email) as email from public.state_club_report_contacts c
    where kind.body='STATE CLUB' and c.is_active and lower(btrim(c.club_name))=lower(btrim(s.club_name))
      and lower(btrim(c.species)) in (species.name,'combined') and nullif(btrim(c.email),'') is not null
    order by (lower(btrim(c.species))=species.name) desc,c.updated_at desc nulls last,c.id limit 1
  ) contact on true
  cross join lateral (select lower(coalesce(contact.email,btrim(s.sweepstakes_email))) as email) destination
  cross join lateral unnest(case
    when kind.body='STATE CLUB' then array['details_by_breed','exh_by_breed','best_display_report']
    when kind.body='NATIONAL CLUB' and species.name='cavy' then
      array['sweepstakes_report','breed_results_detail_report','details_by_breed','exh_by_breed']
    else array['sweepstakes_report','breed_results_detail_report']
  end::public.report_type[]) report(name)
  cross join lateral public.resolve_closeout_artifact_scope(p_show_id,f.id,report.name,
    jsonb_build_object('section_id',sec.id,'section_label',sec.display_name,
      'scope_label',f.scope_label,'scope',upper(sec.kind::text),'show_letter',upper(sec.letter),
      'show_letters',(select array_agg(distinct upper(z.letter)) from public.show_sections z where z.id=any(f.section_ids)),
      'species',species.name,'breed_name',case when kind.body='STATE CLUB' then ''
        when species.name='cavy' then 'Cavy' else btrim(s.breed_name) end,
      'club_name',btrim(s.club_name),'sweepstakes_email',destination.email,
      'sanction_number',changed.number,'sanctioning_body',kind.body,'delivery_type','club',
      'sanction_update_id',s.id)) scope
  where changed.number<>'' and kind.body in ('NATIONAL CLUB','STATE BREED CLUB','STATE CLUB')
    and nullif(btrim(s.club_name),'') is not null
    and destination.email ~ '^[^[:space:],;@]+@[^[:space:],;@]+[.][^[:space:],;@]+$'
    and scope.is_repairable and scope.section_ids=array[sec.id]
    and exists (
      select 1 from public.show_report_artifacts a
      where a.show_id=p_show_id and a.finalize_run_id is not null
        and (a.generated_at is not null or a.metadata ? 'sanction_update_id')
        and a.report_name in ('arba_report','sweepstakes_report','breed_results_detail_report',
          'details_by_breed','exh_by_breed','best_display_report','exhibitor_report','legs')
    );
$$;
revoke all on function private.sanction_club_report_targets(uuid,jsonb) from public,anon,authenticated;

create function public.get_sanction_club_report_options(p_show_id uuid,p_changes jsonb)
returns table(club_name text,recipient text,sections text[],sanction_ids uuid[],report_count bigint)
language sql stable security definer set search_path='' as $$
  select t.club_name,t.recipient,array_agg(distinct t.section_label order by t.section_label),
    array_agg(distinct t.sanction_id),count(distinct t.artifact_key)
  from private.sanction_club_report_targets(p_show_id,p_changes) t
  where auth.uid() is not null and public.user_can_finalize_show(p_show_id,auth.uid())
    and public.user_can_email_reports(p_show_id,auth.uid())
  group by t.club_name,t.recipient order by t.club_name,t.recipient;
$$;
revoke all on function public.get_sanction_club_report_options(uuid,jsonb) from public,anon;
grant execute on function public.get_sanction_club_report_options(uuid,jsonb) to authenticated;

create function public.prepare_sanction_club_reports(
  p_show_id uuid,p_changes jsonb,p_club_name text,p_recipient text,p_report_count integer
) returns table(artifact_id uuid,generation integer)
language plpgsql security definer set search_path='' as $$
declare
  target record;
  artifact public.show_report_artifacts;
  planned_count integer;
begin
  if auth.uid() is null or not coalesce(public.user_can_finalize_show(p_show_id,auth.uid()),false)
    or not coalesce(public.user_can_email_reports(p_show_id,auth.uid()),false) then
    raise exception 'You do not have permission to generate and email club reports.' using errcode='42501';
  end if;
  -- Serialize preparation for this show. Repeated clicks reuse an in-progress
  -- or completed generation with the same sanction and recipient.
  perform pg_advisory_xact_lock(hashtextextended(p_show_id::text||':sanction-club-reports',0));
  select count(distinct t.artifact_key) into planned_count
    from private.sanction_club_report_targets(p_show_id,p_changes) t
    where t.club_name=p_club_name and t.recipient=p_recipient;
  if planned_count=0 or planned_count is distinct from p_report_count then
    raise exception 'The sanctions or report recipients changed. Review them before sending.' using errcode='PT409';
  end if;

  for target in
    select distinct on(t.artifact_key) t.* from private.sanction_club_report_targets(p_show_id,p_changes) t
    where t.club_name=p_club_name and t.recipient=p_recipient
    order by t.artifact_key,t.sanction_id
  loop
    select a.* into artifact from public.show_report_artifacts a
      where a.finalize_run_id=target.finalize_run_id and a.artifact_key=target.artifact_key for update;
    if artifact.id is not null and artifact.is_current
      and artifact.metadata->>'sanction_update_id'=target.sanction_id::text
      and artifact.metadata->>'sanction_number'=target.metadata->>'sanction_number'
      and artifact.metadata->>'sweepstakes_email'=target.recipient
      and (artifact.artifact_status='generated' or exists (
        select 1 from public.show_task_queue q where q.report_artifact_id=artifact.id
          and q.task_type='render_report' and q.task_status in ('queued','running')
      )) then
      return query select artifact.id,artifact.generation;
      continue;
    end if;

    if artifact.id is null then
      insert into public.show_report_artifacts as a
        (show_id,finalize_run_id,report_name,artifact_status,metadata,is_current,scope_key,section_ids,artifact_key)
      values (p_show_id,target.finalize_run_id,target.report_name,'queued',target.metadata,
        true,target.scope_key,target.section_ids,target.artifact_key) returning a.* into artifact;
    else
      update public.show_report_artifacts a
        set metadata=a.metadata||target.metadata,is_current=true,superseded_at=null
        where a.id=artifact.id returning a.* into artifact;
    end if;
    perform public.requeue_single_closeout_artifact(p_show_id,target.finalize_run_id,artifact.scope_key,artifact.id);
    return query select a.id,a.generation from public.show_report_artifacts a where a.id=artifact.id;
  end loop;
end;
$$;
revoke all on function public.prepare_sanction_club_reports(uuid,jsonb,text,text,integer) from public,anon;
grant execute on function public.prepare_sanction_club_reports(uuid,jsonb,text,text,integer) to authenticated;
notify pgrst,'reload schema';
