-- Disposable local fixture only, run by tool/legal_acceptance/test_database.py.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000001',true);
update public.profiles set accepted_privacy_version='2026-10-25-locality',accepted_privacy_at='2026-10-25T18:00Z'
where user_id=auth.uid();
do $$begin
 assert (select accepted_privacy_version='2026-10-25-locality' and accepted_privacy_at='2026-10-25T18:00Z' from public.profiles where user_id=auth.uid()),'new policy can be explicitly accepted';
end$$;
update public.profiles set accepted_privacy_version='2026-10-25-locality',accepted_privacy_at='2026-10-25T19:00Z'
where user_id=auth.uid();
do $$begin
 assert (select accepted_privacy_at='2026-10-25T18:00Z' from public.profiles where user_id=auth.uid()),'repeat agreement preserves the original receipt time';
end$$;
insert into public.profiles(user_id,accepted_terms_version,accepted_terms_at,accepted_privacy_version,accepted_privacy_at)
values(auth.uid(),'2026-05','2026-10-25T20:00Z','2026-05','2026-10-25T20:00Z')
on conflict(user_id) do update set accepted_terms_version=excluded.accepted_terms_version,
 accepted_terms_at=excluded.accepted_terms_at,accepted_privacy_version=excluded.accepted_privacy_version,accepted_privacy_at=excluded.accepted_privacy_at;
do $$begin
 assert (select accepted_privacy_version='2026-10-25-locality' and accepted_privacy_at='2026-10-25T18:00Z' from public.profiles where user_id=auth.uid()),'older tab cannot downgrade privacy agreement';
 assert (select accepted_terms_version='2026-09' and accepted_terms_at='2026-09-01' from public.profiles where user_id=auth.uid()),'older tab cannot downgrade terms agreement';
 assert (select display_name='Keep my name' and email='fixture@example.invalid' from public.profiles where user_id=auth.uid()),'saving agreement preserves profile details';
end$$;
update public.profiles set accepted_privacy_version='2026-10',accepted_privacy_at='2026-10-25T21:00Z' where user_id=auth.uid();
do $$begin
 assert (select accepted_privacy_version='2026-10-25-locality' from public.profiles where user_id=auth.uid()),'intermediate privacy version cannot replace newer receipt';
end$$;
update public.profiles set accepted_privacy_version=null,accepted_privacy_at=null,accepted_terms_version=null,accepted_terms_at=null where user_id=auth.uid();
do $$begin
 assert (select accepted_privacy_version='2026-10-25-locality' and accepted_terms_version='2026-09' from public.profiles where user_id=auth.uid()),'null fields do not erase an existing receipt';
 assert not has_function_privilege('authenticated',(select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='legal_acceptance_private' and p.proname='preserve_profile_acceptance'),'execute'),'trigger function has no public execution grant';
end$$;
select set_config('request.jwt.claim.sub','aaaaaaaa-0000-4000-8000-000000000002',true);
update public.profiles set accepted_privacy_version='2026-09' where user_id='aaaaaaaa-0000-4000-8000-000000000001';
do $$begin
 assert not exists(select from public.profiles where user_id='aaaaaaaa-0000-4000-8000-000000000001'),'another account cannot read or replace the receipt';
 assert (select accepted_privacy_version is null and accepted_terms_version is null from public.profiles where user_id=auth.uid()),'unaccepted policies are never automatically accepted';
end$$;
select '10 legal acceptance database checks passed';
rollback;
