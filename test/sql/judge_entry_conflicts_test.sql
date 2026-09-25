-- Run in a disposable database with the Supabase roles already present.
\set ON_ERROR_STOP on
begin;
create schema auth;
create schema private;
create schema household_private;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function public.user_can_manage_show_lineup(uuid) returns boolean language sql as $$select auth.uid()='00000000-0000-0000-0000-000000000001'::uuid$$;
create table auth.users(id uuid,email text);
create table public.judges(id uuid,email text,first_name text,last_name text,display_name text,name text);
create table public.show_judges(show_id uuid,judge_id uuid);
create table public.judge_assignments(show_id uuid,judge_id uuid);
create table public.show_judging_assignments(show_id uuid,judge_id uuid);
create table public.exhibitors(id uuid,owner_user_id uuid,email text,first_name text,last_name text,display_name text,showing_name text);
create table public.entries(show_id uuid,section_id uuid,exhibitor_id uuid,breed text,status text,scratched_at timestamptz);
create table public.role_assignments(user_id uuid,show_id uuid,role text);
create table public.show_judge_conflict_profiles(user_id uuid,judge_id uuid,exhibitor_id uuid,related_name text,relationship_label text);
create table household_private.invitations(owner_user_id uuid,member_user_id uuid,accepted_at timestamptz,revoked_at timestamptz);
\ir ../../supabase/migrations/20260925020010_judge_entry_conflicts.sql
\ir ../../supabase/migrations/20260925022138_judge_conflict_roster_lookup.sql
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into judges values ('00000000-0000-0000-0000-000000000002','judge@example.test','Pat','Judge',null,null);
insert into judge_assignments values ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002');
insert into exhibitors values
('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000020','judge@example.test','Pat','Judge','Pat Judge',null),
('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000020',null,'Child','Different','Child Different',null),
('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000021',null,'Other','Judge','Other Judge',null),
('00000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000022',null,'Partner','Different','Partner Different',null);
insert into household_private.invitations values ('00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000022',now(),null);
insert into entries select '00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004',id,'Havana','submitted',null from exhibitors;
do $$ begin
 if (select count(distinct exhibitor_id) from get_show_lineup_entry_conflicts('00000000-0000-0000-0000-000000000003'))<>3 then raise exception 'Expected own and two household exhibitors, not shared surname'; end if;
end $$;
update household_private.invitations set revoked_at=now();
update entries set scratched_at=now() where exhibitor_id='00000000-0000-0000-0000-000000000011';
do $$ begin
 if (select count(distinct exhibitor_id) from get_show_lineup_entry_conflicts('00000000-0000-0000-0000-000000000003'))<>1 then raise exception 'Scratched and revoked members must not conflict'; end if;
 if exists(select 1 from validate_show_judge_breed_conflict('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000002','Havana')) then raise exception 'Wrong section included'; end if;
end $$;
insert into show_judge_conflict_profiles values ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000012',null,'Spouse');
do $$ begin
 if (select count(distinct exhibitor_id) from get_show_lineup_entry_conflicts('00000000-0000-0000-0000-000000000003'))<>2 then raise exception 'Explicit relative missing'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000099',false);
set local role authenticated;
do $$ begin
 perform * from public.get_show_lineup_entry_conflicts('00000000-0000-0000-0000-000000000003');
 raise exception 'Unauthorized access allowed';
exception when insufficient_privilege then null;
end $$;
reset role;
rollback;
