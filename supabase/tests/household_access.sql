-- Run after the household migration in a disposable database; rolls back fixtures.
-- Does not send invitations or emails.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('10000000-0000-0000-0000-000000000001','household-owner@example.invalid',now()),
 ('10000000-0000-0000-0000-000000000002','household-member@example.invalid',now()),
 ('10000000-0000-0000-0000-000000000003','household-stranger@example.invalid',now());
insert into public.exhibitors(owner_user_id,display_name,type,is_active,email) values
 ('10000000-0000-0000-0000-000000000001','Test adult','adult',true,'household-member@example.invalid');
insert into public.animals(id,owner_user_id,name) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Household test animal');
insert into public.shows(id,name,owner_user_id) values
 ('30000000-0000-0000-0000-000000000001','Household permissions test','10000000-0000-0000-0000-000000000001');
insert into public.role_assignments(user_id,show_id,role) values
 ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','admin');
insert into public.entry_carts(id,show_id,user_id) values
 ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
create function pg_temp.assert_true(v boolean, message text) returns void language plpgsql as $$
begin if v is distinct from true then raise exception 'FAILED: %', message; end if; end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select pg_temp.assert_true(public.can_access_household(auth.uid()),'Owner access');
do $$
begin
 begin
  perform public.support_household_access('10000000-0000-0000-0000-000000000002');
  raise exception 'FAILED: ordinary login obtained support snapshot';
 exception when insufficient_privilege then null;
 end;
end $$;

select pg_temp.assert_true(public.user_can_manage_show('30000000-0000-0000-0000-000000000001',auth.uid()),'Owner has assigned staff rights');
reset role;
insert into public.exhibitors(owner_user_id,display_name,type,is_active,email,birth_date) values
 ('10000000-0000-0000-0000-000000000001','Younger youth','youth',true,'young@example.invalid',(current_date-interval '13 years')::date),
 ('10000000-0000-0000-0000-000000000001','Unknown youth','youth',true,'unknown@example.invalid',null);
set local role authenticated;
do $$
begin
 begin
  perform public.household_access('invite',null,'young@example.invalid');
  raise exception 'FAILED: Invited youth under 14';
 exception when raise_exception then
  if sqlerrm not like 'Use the email of an active adult%' then raise; end if;
 end;
 begin
  perform public.household_access('invite',null,'unknown@example.invalid');
  raise exception 'FAILED: Invited youth with missing DOB';
 exception when raise_exception then
  if sqlerrm not like 'Use the email of an active adult%' then raise; end if;
 end;
end $$;
select public.household_access('invite',null,' Household-Member@Example.Invalid ');
reset role;
select set_config('test.invitation_id',(select id::text from household_private.invitations where owner_user_id='10000000-0000-0000-0000-000000000001'),true);
select pg_temp.assert_true((select email='household-member@example.invalid' from household_private.invitations where owner_user_id='10000000-0000-0000-0000-000000000001'),'Email normalized');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true(not public.can_access_household('10000000-0000-0000-0000-000000000001'),'Pending invite grants no access');
select pg_temp.assert_true((select count(*)=0 from public.animals where id='20000000-0000-0000-0000-000000000001'),'Pending member cannot read animals');
select public.household_access('accept',((public.household_access()->'invitations')->0->>'id')::uuid);
select pg_temp.assert_true(public.can_access_household('10000000-0000-0000-0000-000000000001'),'Verified recipient can accept');
select pg_temp.assert_true((select count(*)=1 from public.animals where id='20000000-0000-0000-0000-000000000001'),'Accepted member can read animals');
update public.animals set name='Shared edit' where id='20000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select name='Shared edit' from public.animals where id='20000000-0000-0000-0000-000000000001'),'Accepted member can edit animal');
select pg_temp.assert_true(not public.user_can_manage_show('30000000-0000-0000-0000-000000000001',auth.uid()),'Member does not inherit owner staff rights');
select pg_temp.assert_true((select count(*)=1 from public.entry_carts where id='40000000-0000-0000-0000-000000000001'),'Member can read household cart');
select pg_temp.assert_true(not exists(select 1 from public.role_assignments where user_id=auth.uid()),'Membership does not create staff rights');
select pg_temp.assert_true(jsonb_array_length(public.household_access()->'households')=2,'Personal household retained');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select pg_temp.assert_true(not public.can_access_household('10000000-0000-0000-0000-000000000001'),'Stranger denied');
do $$
begin
 begin
  perform public.household_access('accept',current_setting('test.invitation_id')::uuid);
  raise exception 'FAILED: Stranger accepted an invitation';
 exception when raise_exception then
  if sqlerrm not like 'Invitation is unavailable%' then raise; end if;
 end;
 begin
  perform public.household_access('revoke',current_setting('test.invitation_id')::uuid);
  raise exception 'FAILED: Stranger revoked another household';
 exception when raise_exception then
  if sqlerrm <> 'You cannot change this invitation.' then raise; end if;
 end;
end $$;

select pg_temp.assert_true(jsonb_array_length(public.household_access()->'invitations')=0,'Stranger cannot enumerate invitations');
select pg_temp.assert_true((select count(*)=0 from public.animals where id='20000000-0000-0000-0000-000000000001'),'Stranger cannot read animal');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
set local role authenticated;
select public.household_access('revoke',((public.household_access()->'invitations')->0->>'id')::uuid);
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select pg_temp.assert_true(not public.can_access_household('10000000-0000-0000-0000-000000000001'),'Revocation immediate with same JWT');
select pg_temp.assert_true((select count(*)=0 from public.entry_carts where id='40000000-0000-0000-0000-000000000001'),'Revoked member cannot read household cart');
select pg_temp.assert_true((select count(*)=0 from public.animals where id='20000000-0000-0000-0000-000000000001'),'Revoked member cannot read animal');
select pg_temp.assert_true(public.can_access_household(auth.uid()),'Revocation preserves personal household');
reset role;
-- Expired invitations cannot be accepted, even by the right verified email.
update household_private.invitations set revoked_at=null,member_user_id=null,accepted_at=null,expires_at=now()-interval '1 second'
 where id=current_setting('test.invitation_id')::uuid;
set local role authenticated;
do $$
begin
 begin
  perform public.household_access('accept',current_setting('test.invitation_id')::uuid);
  raise exception 'FAILED: Expired invitation accepted';
 exception when raise_exception then
  if sqlerrm <> 'Invitation is unavailable for this login.' then raise; end if;
 end;
end $$;
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.household_access(text,uuid,text)','execute'),'Anonymous invitation API denied');
select pg_temp.assert_true(not has_table_privilege('authenticated','household_private.invitations','insert'),'Membership cannot be forged by direct insert');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)','execute'),'Client cannot spoof payment actor');
rollback;
