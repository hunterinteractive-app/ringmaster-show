begin;
insert into auth.users(id,email,email_confirmed_at) values
('d1100000-0000-0000-0000-000000000001','calendar-owner@example.invalid',now()),
('d1100000-0000-0000-0000-000000000002','calendar-other@example.invalid',now());
insert into public.shows(id,created_by,owner_user_id,name,start_date,end_date,email_sending_disabled)
values('d1200000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','Calendar fixture','2027-01-01','2027-01-02',true);
insert into public.exhibitors(id,owner_user_id,display_name,type,email,phone) values
('d1300000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001','Calendar Owner','adult','calendar-owner@example.invalid','555-0100'),
('d1300000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000002','Calendar Other','adult','calendar-other@example.invalid','555-0101');
insert into public.entries(show_id,exhibitor_id,exhibitor_user_id,tattoo,breed,status)
select 'd1200000-0000-0000-0000-000000000001','d1300000-0000-0000-0000-000000000001','d1100000-0000-0000-0000-000000000001',v,'Dutch',s from (values('ACTIVE','active'),('SUBMITTED','submitted'),('ENTERED','entered'),('CANCELLED','cancelled'),('SCRATCHED','scratched')) as t(v,s);
insert into public.entries(show_id,exhibitor_id,exhibitor_user_id,tattoo,breed,status) values
('d1200000-0000-0000-0000-000000000001','d1300000-0000-0000-0000-000000000002','d1100000-0000-0000-0000-000000000002','PRIVATE','Dutch','active');
set local role service_role;
do $$ declare result jsonb; begin
 select payload into result from public.breeder_calendar_export('d1100000-0000-0000-0000-000000000001');
 if result is null or (result->>'entry_count')::int<>3 then raise exception 'Incorrect active entry count'; end if;
 if result::text like '%PRIVATE%' then raise exception 'Foreign entry leaked'; end if;
 if (select count(*) from public.breeder_calendar_export('d1100000-0000-0000-0000-000000000001'))<>1 then raise exception 'Duplicate show'; end if;
 if exists(select 1 from public.breeder_calendar_export(gen_random_uuid())) then raise exception 'Unknown account saw shows'; end if;
 if exists(select 1 from public.breeder_calendar_export('d1100000-0000-0000-0000-000000000001','d1200000-0000-0000-0000-000000000001')) then raise exception 'Pagination repeated show'; end if;
 if has_function_privilege('anon','public.breeder_calendar_export(uuid,uuid)','execute') or has_function_privilege('authenticated','public.breeder_calendar_export(uuid,uuid)','execute') then raise exception 'Unrestricted export'; end if;
end $$;
update public.entries set scratched_at=now() where tattoo in ('ACTIVE','SUBMITTED','ENTERED') and show_id='d1200000-0000-0000-0000-000000000001';
do $$ begin if exists(select 1 from public.breeder_calendar_export('d1100000-0000-0000-0000-000000000001')) then raise exception 'Removed entries still visible'; end if; end $$;
update public.entries set scratched_at=null where tattoo='ACTIVE' and show_id='d1200000-0000-0000-0000-000000000001';
update public.shows set is_closed=true where id='d1200000-0000-0000-0000-000000000001';
do $$ begin if exists(select 1 from public.breeder_calendar_export('d1100000-0000-0000-0000-000000000001')) then raise exception 'Closed show visible'; end if; end $$;
rollback;
