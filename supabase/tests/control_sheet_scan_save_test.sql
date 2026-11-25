-- Only the local full-e2e synthetic fixture; the runner rolls everything back.
create function pg_temp.scan_check(ok boolean, label text) returns text language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %', label; end if; return 'PASS: '||label; end $$;
create function pg_temp.scan_error(query text, message text) returns boolean language plpgsql as $$
begin execute query; return false; exception when others then
  if position(message in sqlerrm)>0 then return true; end if; raise;
end $$;
create temporary table scan_fixture as select
  '20000000-0000-0000-0000-000000000004'::uuid as show_id,
  '21000000-0000-0000-0000-000000000004'::uuid as section_id,
  '40000000-0000-0000-0000-000000000001'::uuid as first_id,
  '40000000-0000-0000-0000-000000000002'::uuid as second_id,
  (select id from auth.users order by created_at limit 1) as admin_id;
create function pg_temp.scan_snapshot() returns text language sql as $$
  select public.control_sheet_scan_snapshot(show_id,array[section_id]) from scan_fixture;
$$;
create function pg_temp.scan_row(id uuid, status text, place text default null, awards text[] default array[]::text[]) returns jsonb language sql as $$
  select jsonb_build_object('entry_id',id,'result_status',status,'placement',place,'awards',to_jsonb(awards));
$$;
create function pg_temp.scan_save(changes jsonb, snapshot text default null) returns integer language sql as $$
  select public.save_control_sheet_scan(show_id,array[section_id],coalesce(snapshot,pg_temp.scan_snapshot()),changes) from scan_fixture;
$$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
update public.shows set is_locked=false where id=(select show_id from scan_fixture);
delete from public.entry_awards where show_id=(select show_id from scan_fixture);
delete from public.show_result_entry_locks where show_id=(select show_id from scan_fixture);
update public.entries set placement=null,fur_placement=null,result_status='Shown',is_shown=true,
  is_disqualified=false,disqualified_reason=null,scratched_at=null,status='entered'
where show_id=(select show_id from scan_fixture);
insert into public.super_admins(user_id) select admin_id from scan_fixture on conflict do nothing;

select pg_temp.scan_check(not has_function_privilege('anon','public.save_control_sheet_scan(uuid,uuid[],text,jsonb)','execute'),'anonymous has no RPC execute grant');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000099999","role":"authenticated","user_metadata":{"role":"super_admin"}}',true);
select pg_temp.scan_check(pg_temp.scan_error($q$select pg_temp.scan_snapshot()$q$,'Only super admins'),'forged client metadata cannot enable pilot');
select pg_temp.scan_check(pg_temp.scan_error($q$select pg_temp.scan_save('[]')$q$,'Only super admins'),'non-super-admin cannot save');
select set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true) from scan_fixture;
set local role authenticated;
-- Verify authenticated execute permissions, not just privileged SQL execution.
select public.control_sheet_scan_snapshot('20000000-0000-0000-0000-000000000004',array['21000000-0000-0000-0000-000000000004'::uuid]) is not null;
reset role;

create temporary table saved_batch as select
  pg_temp.scan_snapshot() as snapshot,
  jsonb_build_array(pg_temp.scan_row(first_id,'Shown','1',array['BOV','BOB']),pg_temp.scan_row(second_id,'Shown','0')) as changes
from scan_fixture;
select pg_temp.scan_check(pg_temp.scan_save(changes,snapshot)=2,'confirmed batch saves placement, NP and specials') from saved_batch;
select pg_temp.scan_check(e.placement='1' and e.result_status='Shown' and e.result_entered_by_user_id=f.admin_id,'normal result audit fields saved') from entries e,scan_fixture f where e.id=f.first_id;
select pg_temp.scan_check(count(*)=2,'special awards persisted') from entry_awards a,scan_fixture f where a.entry_id=f.first_id;
create temporary table after_save as select pg_temp.scan_snapshot() as snapshot;
select pg_temp.scan_check(pg_temp.scan_save(changes,snapshot)=2,'response-loss retry succeeds') from saved_batch;
select pg_temp.scan_check(pg_temp.scan_snapshot()=snapshot,'retry does not rewrite entries or award timestamps') from after_save;
set constraints all immediate;
set constraints all deferred;

-- Changes made by someone else after validation cannot be overwritten.
create temporary table before_change as select pg_temp.scan_snapshot() as snapshot;
update entries set tattoo=tattoo||'-edited' where id=(select second_id from scan_fixture);
select pg_temp.scan_check(pg_temp.scan_error($q$select pg_temp.scan_save(jsonb_build_array(pg_temp.scan_row(first_id,'Shown','2')),(select snapshot from before_change)) from scan_fixture$q$,'changed during review'),'stale roster snapshot rejected');
select pg_temp.scan_check(placement='1','stale save left prior result untouched') from entries where id=(select first_id from scan_fixture);

-- A bad later row rolls back the whole batch.
delete from entry_awards where entry_id=(select first_id from scan_fixture);
update entries set placement=null where id in (select first_id from scan_fixture union select second_id from scan_fixture);
select pg_temp.scan_check(pg_temp.scan_error($q$select pg_temp.scan_save(jsonb_build_array(pg_temp.scan_row(first_id,'Shown','2'),pg_temp.scan_row('00000000-0000-4000-8000-000000088888','Shown','1'))) from scan_fixture$q$,'no longer in this show'),'unknown row rejects batch');
select pg_temp.scan_check(placement is null,'no partial save after bad row') from entries where id=(select first_id from scan_fixture);
update entries e set variety=a.variety,class_name=a.class_name,sex=a.sex from entries a,scan_fixture f where e.id=f.second_id and a.id=f.first_id;
select pg_temp.scan_check(pg_temp.scan_error($q$select pg_temp.scan_save(jsonb_build_array(pg_temp.scan_row(first_id,'Shown','1'),pg_temp.scan_row(second_id,'Shown','1'))) from scan_fixture$q$,'same placement'),'duplicate class ranks rejected after writes');
select pg_temp.scan_check(bool_and(placement is null),'duplicate-rank failure rolled back every write') from entries where id in (select first_id from scan_fixture union select second_id from scan_fixture);
select pg_temp.scan_check(pg_temp.scan_error($q$select save_control_sheet_scan(show_id,array['21000000-0000-0000-0000-000000000001'::uuid],pg_temp.scan_snapshot(),jsonb_build_array(pg_temp.scan_row(first_id,'Shown','1'))) from scan_fixture$q$,'section is unavailable'),'foreign section rejected');

-- Every outcome uses canonical Results Entry flags and reason strings.
do $$
declare s text; f record; before_retry text; payload jsonb;
begin
 select * into f from scan_fixture;
 foreach s in array array['No Show','Scratched','Unworthy of Award','Disqualified - Wrong Sex','Disqualified - Wrong Variety','Disqualified - Wrong Class','Disqualified - Overweight','Disqualified - Wrong Tattoo','Disqualified - Other'] loop
  update entries set placement=null,result_status='Shown',is_shown=true,is_disqualified=false,disqualified_reason=null,scratched_at=null,status='entered' where id=f.first_id;
  payload := jsonb_build_array(pg_temp.scan_row(f.first_id,s));
  perform pg_temp.scan_save(payload);
  perform pg_temp.scan_check((select result_status=s and is_shown=(s not in ('No Show','Scratched')) and is_disqualified=(s like 'Disqualified - %') and disqualified_reason is not distinct from (case when s like 'Disqualified - %' then substr(s,16) end) and placement is null and (s<>'Scratched' or (scratched_at is not null and status='scratched')) from entries where id=f.first_id),'outcome '||s);
  before_retry := pg_temp.scan_snapshot();
  perform pg_temp.scan_save(payload);
  perform pg_temp.scan_check(pg_temp.scan_snapshot()=before_retry,'outcome retry '||s);
 end loop;
end $$;
select pg_temp.scan_check(count(*)=1,'scratch retry creates one scratch audit event') from public.show_checkin_audit_events where show_id=(select show_id from scan_fixture) and event_type='entry_scratched' and details->>'entry_id'=(select first_id::text from scan_fixture);
update shows set is_locked=true where id=(select show_id from scan_fixture);
select pg_temp.scan_check(pg_temp.scan_error($q$select pg_temp.scan_save('[]')$q$,'locked or unavailable'),'locked shows rejected');
set constraints all immediate;
