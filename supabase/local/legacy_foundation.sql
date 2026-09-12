-- LOCAL ONLY: historical contracts needed before replaying tracked migrations.
-- The loader-only fixture deliberately has a smaller reporting view. This file
-- restores the older aggregate shape which subsequent migrations replace.
-- No hosted data or schema export is used. Do not apply to an existing project.

create table public.sweepstakes_results (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid references public.shows(id), breed_name text,
  exhibitor_id text, exhibitor_name text, scope text, show_letter text,
  class_points numeric default 0, variety_points numeric default 0,
  group_points numeric default 0, bob_points numeric default 0,
  bis_points numeric default 0, fur_points numeric default 0,
  total_points numeric default 0, calculation_version text,
  rule_source text, verification_status text, engine_type text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
alter table public.sweepstakes_results enable row level security;
grant select on public.sweepstakes_results to authenticated;
grant all on public.sweepstakes_results to service_role;

alter table public.sweepstakes_entry_results
  add column animal_id uuid, add column breed_name text, add column variety_name text,
  add column class_name text, add column sex text, add column tattoo text,
  add column show_letter text, add column scope text, add column points_source text;
alter table public.entries add column special_awards text,
  add column breed_id uuid references public.breeds(id),
  add column variety_id uuid references public.varieties(id);

-- No dependent objects exist at this point in a fresh local bootstrap.
drop view public.v_sweepstakes_pdf_rows;
create or replace view public.v_sweepstakes_pdf_rows
with (security_invoker = true)
as
select
  sr.show_id,
  sr.breed_name,
  sr.scope,
  sr.show_letter,
  sr.exhibitor_id,
  sr.exhibitor_name,
  concat_ws(
    ', ',
    nullif(e.address_line1, ''),
    nullif(e.city, ''),
    nullif(e.state, ''),
    nullif(e.zip, '')
  ) as exhibitor_address,
  sr.class_points,
  sr.class_points as arba_class_points,
  sr.variety_points,
  sr.group_points,
  sr.bob_points,
  sr.bis_points,
  sr.fur_points,
  sr.total_points,
  sr.calculation_version,
  sr.rule_source,
  sr.verification_status,
  sr.engine_type,
  ''::text as arba_sanction_number,
  ''::text as national_club_sanction_number,
  c.name as host_club_name,
  s.location_name as show_location,
  ''::text as secretary_name,
  s.secretary_email,
  s.secretary_phone,
  row_number() over (
    partition by sr.show_id, sr.breed_name, sr.scope, sr.show_letter
    order by sr.total_points desc, sr.class_points desc, sr.exhibitor_name
  ) as rank
from public.sweepstakes_results sr
left join public.exhibitors e on e.id::text = sr.exhibitor_id
left join public.shows s on s.id = sr.show_id
left join public.clubs c on c.id = s.club_id
where sr.calculation_version in ('v2', 'cavy-fixed-v1');

-- The historical three-argument overload is not used by the local fixture.
-- Fail explicitly rather than inventing a legacy scoring implementation.
create function public.calculate_sweepstakes_for_breed(uuid, text, text)
returns setof public.sweepstakes_results language plpgsql set search_path='' as $$
begin
  raise exception 'Local fixture requires the explicit four-argument scoring API';
end $$;

create table public.processed_stripe_sessions (
  stripe_session_id text primary key, secretary_email text,
  matched_user_id uuid, matched_plan text, processed_at timestamptz default now()
);
alter table public.processed_stripe_sessions enable row level security;
grant all on public.processed_stripe_sessions to service_role;

create table public.show_payment_accounts (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id),
  provider text, account_id text, created_at timestamptz default now()
);
alter table public.show_payment_accounts enable row level security;
alter table public.show_payment_account_links enable row level security;
grant all on public.show_payment_accounts, public.show_payment_account_links to service_role;
grant select, insert, update on public.show_payment_accounts, public.show_payment_account_links to authenticated;

create type public.species as enum ('rabbit', 'cavy');

alter table public.varieties add column updated_at timestamptz default now();
create table public.point_place_scale (
  place_number integer primary key, place_points numeric not null
);
alter table public.point_place_scale enable row level security;
grant select on public.point_place_scale to authenticated;
grant all on public.point_place_scale to service_role;

create table public.breed_rules_matrix (
  breed_name text primary key,
  engine_family text,
  class_points_model text,
  placement_depth integer default 5,
  multiplier_type text,
  place_1 numeric default 0,
  place_2 numeric default 0,
  place_3 numeric default 0,
  place_4 numeric default 0,
  place_5 numeric default 0,
  uses_variety_points boolean default false,
  uses_group_points boolean default false,
  uses_bob_points boolean default false,
  uses_bos_points boolean default false,
  uses_bis_points boolean default false,
  uses_ris_points boolean default false,
  uses_fur_points boolean default false,
  uses_best4class_points boolean default false,
  uses_participation_points boolean default false,
  bov_points numeric default 0,
  bosv_points numeric default 0,
  bog_points numeric default 0,
  bosg_points numeric default 0,
  bob_points numeric default 0,
  bosb_points numeric default 0,
  bis_points numeric default 0,
  bris_points numeric default 0,
  fur_points numeric default 0,
  best4class_points numeric default 0,
  participation_points numeric default 0,
  bob_basis text,
  bos_basis text,
  bov_basis text,
  bosv_basis text,
  bis_basis text,
  ris_basis text,
  fur_basis text,
  convention_override boolean default false,
  national_override boolean default false,
  specialty_override boolean default false,
  membership_required boolean default false,
  sanction_required boolean default false,
  tracks_open boolean default false,
  tracks_youth boolean default false,
  rule_source text,
  verification_status text,
  status text,
  notes text,
  national_notes text,
  specialty_notes text,
  updated_at timestamptz default now()
);
alter table public.breed_rules_matrix enable row level security;
grant select on public.breed_rules_matrix to authenticated;
grant all on public.breed_rules_matrix to service_role;

alter table public.shows add column final_award_mode text default 'four_six_bis';
-- SQL migrations consume named result columns, whereas the loader fixture
-- exposes JSON rows. Preserve the fixture function for its existing callers.
alter function public.report_results_entry_rows(uuid, uuid, text)
  rename to report_results_entry_rows_loader_fixture;
alter table public.entries alter column placement type text using placement::text;
alter table public.breeds add column is_active boolean default true;
create table public.show_exhibitor_numbers (
 id uuid primary key default extensions.gen_random_uuid(),
 show_id uuid references public.shows(id), exhibitor_id uuid references public.exhibitors(id),
 exhibitor_number text, unique(show_id, exhibitor_id)
);
alter table public.show_exhibitor_numbers enable row level security;
grant all on public.show_exhibitor_numbers to service_role;
create or replace function public.report_results_entry_rows(
  p_show_id uuid,
  p_section_id uuid default null,
  p_show_letter text default null
)
returns table(
  entry_id uuid,
  section_id uuid,
  exhibitor_id uuid,
  exhibitor_label text,
  exhibitor_number text,
  exhibitor_showing_name text,
  exhibitor_first_name text,
  exhibitor_last_name text,
  exhibitor_address_line1 text,
  exhibitor_address_line2 text,
  exhibitor_city text,
  exhibitor_state text,
  exhibitor_zip text,
  breed text,
  breed_id uuid,
  breed_name text,
  variety text,
  variety_name text,
  fur_variety text,
  group_name text,
  class_name text,
  sex text,
  tattoo text,
  placement text,
  result_status text,
  is_shown boolean,
  is_disqualified boolean,
  disqualified_reason text,
  scratched_at timestamptz,
  judged_by_show_judge_id uuid,
  is_fur boolean,
  uses_group_awards boolean,
  uses_variety_awards boolean,
  breed_sort_order integer,
  group_sort_order integer,
  variety_sort_order integer,
  class_sort_order integer
)
language sql
stable
security definer
set search_path = public
as $$
select distinct on (e.id)
  e.id as entry_id,
  e.section_id,
  e.exhibitor_id,
  coalesce(
    nullif(ex.display_name, ''),
    nullif(ex.showing_name, ''),
    nullif(trim(concat_ws(' ', ex.first_name, ex.last_name)), ''),
    ''
  )::text as exhibitor_label,
  coalesce(ex.exhibitor_number::text, sen.exhibitor_number::text, '')::text as exhibitor_number,
  coalesce(ex.showing_name, '')::text as exhibitor_showing_name,
  coalesce(ex.first_name, '')::text as exhibitor_first_name,
  coalesce(ex.last_name, '')::text as exhibitor_last_name,
  coalesce(ex.address_line1, '')::text as exhibitor_address_line1,
  coalesce(ex.address_line2, '')::text as exhibitor_address_line2,
  coalesce(ex.city, '')::text as exhibitor_city,
  coalesce(ex.state, '')::text as exhibitor_state,
  coalesce(ex.zip, '')::text as exhibitor_zip,
  coalesce(e.breed, '')::text as breed,
  b.id as breed_id,
  coalesce(b.name, e.breed, '')::text as breed_name,
  coalesce(e.variety, '')::text as variety,
  coalesce(v.name, e.variety, '')::text as variety_name,
  coalesce(e.fur_variety, '')::text as fur_variety,
  case when coalesce(e.is_fur, false) then 'Fur / Wool' else coalesce(vg.name, '')::text end::text as group_name,
  coalesce(e.class_name, '')::text as class_name,
  coalesce(e.sex, '')::text as sex,
  coalesce(e.tattoo, '')::text as tattoo,
  case when coalesce(e.is_fur, false) then e.fur_placement::text else e.placement::text end as placement,
  case
    when lower(coalesce(e.result_status, '')) like 'disqualified%' then e.result_status::text
    when coalesce(e.is_disqualified, false) then ('Disqualified - ' || coalesce(nullif(trim(e.disqualified_reason), ''), 'Other'))::text
    else coalesce(e.result_status, 'Shown')::text
  end as result_status,

  case
    when coalesce(e.is_fur, false) = true then
      (
        e.fur_placement is not null
        and e.fur_placement > 0
      )
    else coalesce(e.is_shown, true)
  end::boolean as is_shown,
  coalesce(e.is_disqualified, false)::boolean as is_disqualified,
  coalesce(e.disqualified_reason, '')::text as disqualified_reason,
  e.scratched_at,
  e.judged_by_show_judge_id,
  coalesce(e.is_fur, false)::boolean as is_fur,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_group_awards, false) end::boolean as uses_group_awards,
  case when coalesce(e.is_fur, false) then false else coalesce(b.uses_variety_awards, false) end::boolean as uses_variety_awards,
  0::integer as breed_sort_order,
  case when coalesce(e.is_fur, false) then 9999 when vg.id is null then 9998 else coalesce(vg.sort_order, 9998)::integer end as group_sort_order,
  case when coalesce(e.is_fur, false) then 9999 else coalesce(v.sort_order, 9999)::integer end as variety_sort_order,
  case
    when coalesce(e.is_fur, false) then 1000
    when lower(coalesce(e.class_name, '')) like '%senior%' then 0
    when lower(coalesce(e.class_name, '')) like '%intermediate%' then 1
    when lower(coalesce(e.class_name, '')) like '%junior%' then 2
    else 99
  end::integer as class_sort_order
from public.entries e
left join public.exhibitors ex on ex.id = e.exhibitor_id
left join lateral (
  select sen.* from public.show_exhibitor_numbers sen
  where sen.show_id = e.show_id and sen.exhibitor_id = e.exhibitor_id
  order by sen.exhibitor_number nulls last, sen.id limit 1
) sen on true
left join lateral (
  select b.* from public.breeds b
  where b.is_active = true
    and lower(trim(b.name)) = lower(trim(e.breed))
    and lower(b.species::text) = lower(e.species::text)
  order by b.name, b.id limit 1
) b on true
left join lateral (
  select v.* from public.varieties v
  where v.breed_id = b.id and lower(trim(v.name)) = lower(trim(e.variety))
  order by v.sort_order nulls last, v.name, v.id limit 1
) v on true
left join public.variety_groups vg on vg.id = v.group_id
left join public.show_sections s on s.id = e.section_id
where e.show_id = p_show_id
  and (p_section_id is null or e.section_id = p_section_id)
  and (p_show_letter is null or p_show_letter = '' or upper(coalesce(s.letter::text, '')) = upper(p_show_letter))
order by e.id, breed, group_sort_order, group_name, variety_sort_order, variety, class_sort_order, sex, tattoo;
$$;

revoke all on function public.report_results_entry_rows(uuid, uuid, text) from public, anon;
grant execute on function public.report_results_entry_rows(uuid, uuid, text) to authenticated, service_role;

create table public.profiles (
  id uuid primary key references auth.users(id),
  primary_exhibitor_id uuid references public.exhibitors(id)
);
create table public.club_members (
  club_id uuid references public.clubs(id), user_id uuid references auth.users(id),
  role text, is_active boolean default true, primary key(club_id, user_id)
);
alter table public.clubs add column is_active boolean default true;
alter table public.exhibitors add column is_active boolean default true,
  add column is_merged boolean default false, add column merged_into_exhibitor_id uuid,
  add column merged_at timestamptz, add column updated_at timestamptz default now();
create table public.exhibitor_merge_log (
  id uuid primary key default extensions.gen_random_uuid(),
  kept_exhibitor_id uuid references public.exhibitors(id),
  merged_exhibitor_id uuid references public.exhibitors(id), reason text,
  merged_snapshot jsonb, created_at timestamptz default now()
);
create table public.entry_correction_audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid references public.shows(id), entry_id uuid references public.entries(id),
  field_name text, old_value text, new_value text, reason text, writer_name text,
  approved_by_user_id uuid, approved_by_role text, created_at timestamptz default now()
);
alter table public.profiles enable row level security;
alter table public.club_members enable row level security;
alter table public.exhibitor_merge_log enable row level security;
alter table public.entry_correction_audit_log enable row level security;
grant all on public.profiles, public.club_members, public.exhibitor_merge_log, public.entry_correction_audit_log to service_role;

-- Standard display-point fixture, using the field contract preserved in
-- 20260729193950. Later migrations apply dated club schedules to these rows.
create function public.report_best_display_entry_rows(
  p_show_id uuid, p_scope text default null, p_show_letter text default null
)
returns table(
  show_id uuid, section_id uuid, scope text, show_letter text, species text,
  exhibitor_id uuid, exhibitor_name text, entry_id uuid, breed_name text,
  variety_name text, group_name text, class_name text, sex text, tattoo text,
  placement integer, animals_judged integer, placement_multiplier integer,
  display_points numeric, is_point_earning boolean
)
language sql stable security invoker set search_path='' as $$
with eligible as (
 select e.*, upper(s.kind) as scope, upper(s.letter) as show_letter,
  coalesce(x.display_name, x.showing_name, concat_ws(' ', x.first_name, x.last_name)) as exhibitor_name,
  count(*) over(partition by e.section_id, e.species, e.breed, e.variety, e.class_name, e.sex)::integer as animals_judged,
  case when e.placement ~ '^[0-9]+$' then e.placement::integer end as placing_number
 from public.entries e join public.show_sections s on s.id=e.section_id
 left join public.exhibitors x on x.id=e.exhibitor_id
 where e.show_id=p_show_id and e.scratched_at is null and coalesce(e.is_shown,true)
  and not coalesce(e.is_disqualified,false) and not coalesce(e.is_fur,false)
  and (p_scope is null or upper(s.kind)=upper(p_scope))
  and (p_show_letter is null or upper(s.letter)=upper(p_show_letter))
), points as (
 select e.*, case placing_number when 1 then 6 when 2 then 4 when 3 then 3 when 4 then 2 when 5 then 1 else 0 end as multiplier
 from eligible e
)
select e.show_id,e.section_id,e.scope,e.show_letter,e.species,e.exhibitor_id,e.exhibitor_name,
 e.id,e.breed,e.variety,e.group_name,e.class_name,e.sex,e.tattoo,e.placing_number,
 e.animals_judged,e.multiplier,(e.animals_judged*e.multiplier)::numeric,e.multiplier>0
from points e order by e.section_id,e.exhibitor_id,e.id
$$;
revoke all on function public.report_best_display_entry_rows(uuid,text,text) from public,anon;
grant execute on function public.report_best_display_entry_rows(uuid,text,text) to authenticated,service_role;

-- Keep authorization compatible with the original super_admins table while
-- the app also supports the newer role_assignments model.  Several Closeout
-- V2 RPCs authorize through these shared helpers.
create or replace function public.is_super_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.super_admins sa
    where sa.user_id = uid
  )
  or exists (
    select 1
    from public.role_assignments ra
    where ra.user_id = uid
      and ra.role = 'super_admin'
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_super_admin(auth.uid());
$$;


revoke all on function public.is_super_admin(), public.is_super_admin(uuid) from public, anon;
grant execute on function public.is_super_admin(), public.is_super_admin(uuid) to authenticated, service_role;
create function public.prevent_entry_changes_when_locked()
returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.shows s where s.id=old.show_id and s.is_locked) then
    raise exception 'Show is locked' using errcode='42501';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
create trigger prevent_entry_changes_when_locked before update or delete on public.entries
for each row execute function public.prevent_entry_changes_when_locked();

create table public.show_breeds (
  show_id uuid references public.shows(id), breed_id uuid references public.breeds(id),
  is_enabled boolean default true, primary key(show_id,breed_id)
);
create table public.show_varieties (
  show_id uuid references public.shows(id), variety_id uuid references public.varieties(id),
  is_enabled boolean default true, primary key(show_id,variety_id)
);
alter table public.show_breeds enable row level security;
alter table public.show_varieties enable row level security;
grant all on public.show_breeds,public.show_varieties to service_role;
grant select,insert,update,delete on public.show_breeds,public.show_varieties to authenticated;

-- These background jobs are part of tracked migrations. Use the actual local
-- Supabase extension rather than substituting a scheduler in the test fixture.
create extension if not exists pg_cron;
alter table public.shows add column locked_at timestamptz;
alter table public.show_varieties drop constraint show_varieties_pkey;
alter table public.show_varieties add column id uuid primary key default extensions.gen_random_uuid(),
 add column breed_id uuid references public.breeds(id), add column custom_name text;

create table public.show_email_deliveries (
 id uuid primary key default extensions.gen_random_uuid(),
 show_id uuid references public.shows(id), artifact_id uuid references public.show_report_artifacts(id),
 report_name public.report_type, recipient_email text, recipient_name text, subject text,
 delivery_type text, delivery_status text, error_message text, provider_message_id text, sent_at timestamptz, created_at timestamptz default now()
);
alter table public.show_email_deliveries enable row level security;
grant all on public.show_email_deliveries to service_role;

create view public.report_entry_base_v with(security_invoker=true) as
select e.id as entry_id,e.show_id,e.section_id,e.exhibitor_id,
 coalesce(x.display_name,x.showing_name,concat_ws(' ',x.first_name,x.last_name)) as exhibitor_label,
 x.showing_name as exhibitor_showing_name,x.display_name as exhibitor_display_name,
 x.first_name as exhibitor_first_name,x.last_name as exhibitor_last_name,
 x.arba_number as exhibitor_arba_number,x.address_line1 as exhibitor_address_line1,
 x.address_line2 as exhibitor_address_line2,x.city as exhibitor_city,x.state as exhibitor_state,
 x.zip as exhibitor_zip,x.phone as exhibitor_phone,x.email as exhibitor_email,
 s.letter as section_letter,s.display_name as section_display_name,s.kind as section_kind,
 s.sort_order as section_sort_order,e.species,e.breed,e.group_name,
 coalesce(g.sort_order,9999) as group_sort_order,e.variety,
 coalesce(v.sort_order,9999) as variety_sort_order,e.sex,e.class_name,
 regexp_replace(e.class_name,' (Buck|Doe|Boar|Sow)$','','i') as class_age_label,
 case when e.class_name ilike '%senior%' then 0 when e.class_name ilike '%intermediate%' then 1
 when e.class_name ilike '%pre%junior%' then 3 when e.class_name ilike '%junior%' then 2 else 99 end as class_sort_order,
 e.tattoo,e.scratched_at,e.created_at
from public.entries e join public.show_sections s on s.id=e.section_id
left join public.exhibitors x on x.id=e.exhibitor_id
left join public.varieties v on v.id=e.variety_id
left join public.variety_groups g on g.id=v.group_id;
grant select on public.report_entry_base_v to authenticated,service_role;

alter table public.breeds add column class_system text default 'four';
alter table public.show_breeds add column class_system_override text;

-- Reference catalog rows are prerequisites for tracked data corrections.
insert into public.breeds(id,name,species,class_system) values
 ('10000000-0000-0000-0000-000000000005','Netherland Dwarf','rabbit','four');
insert into public.varieties(id,breed_id,name) values
 ('12000000-0000-0000-0000-000000000006','10000000-0000-0000-0000-000000000005','Black Tortoise Shell');
create table public.show_results_raw (
 id uuid primary key default extensions.gen_random_uuid(), show_id uuid references public.shows(id),
 section_id uuid references public.show_sections(id), breed_name text, variety_name text
);
create table public.show_payback_schedules (
 id uuid primary key default extensions.gen_random_uuid(), show_id uuid references public.shows(id),
 section_id uuid references public.show_sections(id), applies_to text, is_enabled boolean default true
);
create table public.show_payback_schedule_rows (
 id uuid primary key default extensions.gen_random_uuid(), schedule_id uuid references public.show_payback_schedules(id),
 placement integer, applies_to_species text, min_shown integer, max_shown integer, amount_cents integer
);
create table public.show_special_money_rules (
 id uuid primary key default extensions.gen_random_uuid(), show_id uuid references public.shows(id),
 section_id uuid references public.show_sections(id), award_code text, award_label text,
 is_enabled boolean default true, amount_cents integer, applies_to_species text,
 breed_name text, variety_name text
);
alter table public.show_results_raw enable row level security;
alter table public.show_payback_schedules enable row level security;
alter table public.show_payback_schedule_rows enable row level security;
alter table public.show_special_money_rules enable row level security;
grant all on public.show_results_raw, public.show_payback_schedules, public.show_payback_schedule_rows, public.show_special_money_rules to service_role;

create function public.ordinal_suffix(p_number integer) returns text
language sql immutable set search_path='' as $$
 select case when abs(p_number)%100 between 11 and 13 then 'th'
 when abs(p_number)%10=1 then 'st' when abs(p_number)%10=2 then 'nd'
 when abs(p_number)%10=3 then 'rd' else 'th' end
$$;
create function public.report_best_display_standings(
 p_show_id uuid, p_scope text default null, p_show_letter text default null,
 p_minimum_entries integer default 6
)
returns table(
 section_id uuid, scope text, show_letter text, species text,
 exhibitor_id uuid, exhibitor_name text, qualifying_entry_count integer,
 display_points numeric, rank bigint, is_eligible boolean, is_winner boolean, is_tied boolean
)
language sql stable security invoker set search_path='' as $$
with totals as (
 select r.section_id,r.scope,r.show_letter,r.species,r.exhibitor_id,max(r.exhibitor_name) as exhibitor_name,
 count(*)::integer as qualifying_entry_count,sum(r.display_points) as display_points
 from public.report_best_display_entry_rows(p_show_id,p_scope,p_show_letter) r
 where r.is_point_earning
 group by r.section_id,r.scope,r.show_letter,r.species,r.exhibitor_id
), ranked as (
 select t.*,t.qualifying_entry_count>=p_minimum_entries as is_eligible,
 rank() over(partition by t.section_id,t.species order by (t.qualifying_entry_count>=p_minimum_entries) desc,t.display_points desc) as standing_rank,
 count(*) over(partition by t.section_id,t.species,(t.qualifying_entry_count>=p_minimum_entries),t.display_points)>1 as is_tied
 from totals t
)
select r.section_id,r.scope,r.show_letter,r.species,r.exhibitor_id,r.exhibitor_name,
 r.qualifying_entry_count,r.display_points,r.standing_rank,r.is_eligible,
 r.is_eligible and r.standing_rank=1 and not r.is_tied,r.is_tied
from ranked r order by r.section_id,r.species,r.standing_rank,r.exhibitor_id
$$;
revoke all on function public.report_best_display_standings(uuid,text,text,integer) from public,anon;
grant execute on function public.report_best_display_standings(uuid,text,text,integer) to authenticated,service_role;
alter table public.show_results_raw add column class_name text;
alter table public.breeds add column has_prejunior boolean default false;
alter table public.show_closeout_state add column updated_at timestamptz default now();
alter table public.animals add column exhibitor_id uuid references public.exhibitors(id);

-- The local print-pack fixture grants email permission only to show managers.
-- This is conservative; it does not infer additional production role grants.
create function public.user_can_email_reports(p_show_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select public.user_can_manage_show_settings(p_show_id,p_user_id)
$$;
revoke all on function public.user_can_email_reports(uuid,uuid) from public,anon;
grant execute on function public.user_can_email_reports(uuid,uuid) to authenticated,service_role;

-- The tracked print-pack migration references two fixed account IDs. Satisfy
-- those foreign keys with disabled synthetic Auth records, never real users.
insert into auth.users(id,aud,role,email,encrypted_password,banned_until,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('3e8dddf9-3a17-4ebb-aeab-9b51d31e7871','authenticated','authenticated','local-print-pack-1@example.invalid','', 'infinity','{}','{"fixture":true}',now(),now()),
 ('cad4eb5f-239a-4990-b372-e8a43e3faee8','authenticated','authenticated','local-print-pack-2@example.invalid','', 'infinity','{}','{"fixture":true}',now(),now());

alter table public.show_sanctions add column updated_at timestamptz default now();
alter table public.show_sanctions add column request_status text;

-- Historical results permission contract, also recorded in
-- e2e_historical_contracts.json. Database-only tests need it before prepare.py.
create function public.user_can_enter_results(p_show_id uuid, p_user_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select public.user_can_manage_show_settings(p_show_id,coalesce(p_user_id,auth.uid()))
   or exists (select 1 from public.role_assignments ra
     where ra.show_id=p_show_id and ra.user_id=coalesce(p_user_id,auth.uid())
       and ra.role::text='reporting_clerk')
$$;
revoke all on function public.user_can_enter_results(uuid,uuid) from public,anon;
grant execute on function public.user_can_enter_results(uuid,uuid) to authenticated,service_role;
