begin;
insert into auth.users(id,email,email_confirmed_at) values ('d2100000-0000-0000-0000-000000000001','favorite-test@example.invalid',now()),('d2100000-0000-0000-0000-000000000002','favorite-other@example.invalid',now());
insert into public.shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,entry_close_at,email_sending_disabled) values ('d2200000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','d2100000-0000-0000-0000-000000000001','Favorite test','2027-01-05','2027-01-05',true,'2027-01-01T17:00:00Z',true);
set local role authenticated;
select set_config('request.jwt.claim.sub','d2100000-0000-0000-0000-000000000001',true);
insert into public.show_favorites(user_id,show_id) values('d2100000-0000-0000-0000-000000000001','d2200000-0000-0000-0000-000000000001');
do $$ begin
 begin insert into public.show_favorites(user_id,show_id) values('d2100000-0000-0000-0000-000000000002','d2200000-0000-0000-0000-000000000001'); raise exception 'Foreign insert allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','d2100000-0000-0000-0000-000000000002',true);
do $$ begin
 if exists(select 1 from public.show_favorites) then raise exception 'Private favorites leaked'; end if;
 delete from public.show_favorites where user_id='d2100000-0000-0000-0000-000000000001';
 if found then raise exception 'Foreign deletion allowed'; end if;
end $$;
reset role;
set local role service_role;
do $$ declare p jsonb; begin
 select payload into p from public.breeder_calendar_export('d2100000-0000-0000-0000-000000000001');
 if p is null or p->>'is_favorite'<>'true' or (p->>'entry_count')::int<>0 or (p->>'entry_close_at')::timestamptz<>'2027-01-01T17:00:00Z'::timestamptz then raise exception 'Favorite export failed'; end if;
 if exists(select 1 from public.breeder_calendar_export('d2100000-0000-0000-0000-000000000002')) then raise exception 'Export leaked favorite'; end if;
end $$;
update public.shows set is_published=false where id='d2200000-0000-0000-0000-000000000001';
do $$ begin if exists(select 1 from public.breeder_calendar_export('d2100000-0000-0000-0000-000000000001')) then raise exception 'Unpublished show exported'; end if; end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2100000-0000-0000-0000-000000000001',true);
delete from public.show_favorites where show_id='d2200000-0000-0000-0000-000000000001';
reset role;
do $$ begin if exists(select 1 from public.show_favorites where show_id='d2200000-0000-0000-0000-000000000001') then raise exception 'Unfavorite failed'; end if; end $$;
rollback;
