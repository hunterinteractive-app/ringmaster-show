begin;
insert into auth.users(id,email) values('94000000-0000-0000-0000-000000000001','faq-admin@example.invalid'),('94000000-0000-0000-0000-000000000002','faq-user@example.invalid');
insert into public.super_admins(user_id) values('94000000-0000-0000-0000-000000000001');
insert into assistant_private.conversations(id,actor_id) values('95000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000002');
insert into assistant_private.messages(id,conversation_id,ordinal,role,content,page,topic,source) values
('96000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',0,'user','How do I prepare a show?','Setup','help','chat'),
('96000000-0000-0000-0000-000000000002','95000000-0000-0000-0000-000000000001',1,'assistant','Contact private@example.invalid then review setup.','Setup','help','ai');
set local role authenticated;
select set_config('request.jwt.claim.sub','94000000-0000-0000-0000-000000000001',true);
do $$ declare d jsonb; v uuid; begin
 d:=public.chester_answer_admin('create',p_source=>'96000000-0000-0000-0000-000000000002'); v:=(d->>'id')::uuid;
 if d->>'answer' like '%private@example.invalid%' then raise exception 'FAIL redaction'; end if;
 if public.chester_match_answer('How do I prepare a show?') is not null then raise exception 'FAIL draft visible'; end if;
 begin perform public.chester_answer_admin('publish',v,p_question=>'How do I prepare a show?',p_answer=>'Reviewed steps',p_version=>1); raise exception 'FAIL unreviewed publish'; exception when others then if sqlerrm='FAIL unreviewed publish' then raise; end if; end;
 d:=public.chester_answer_admin('publish',v,p_question=>'How do I prepare a show?',p_answer=>'Reviewed steps',p_aliases=>array['How can I prepare a show?'],p_version=>1,p_reviewed=>true);
 if public.chester_match_answer(' HOW CAN I PREPARE A SHOW!!! ')->>'answer'<>'Reviewed steps' then raise exception 'FAIL alias'; end if;
 d:=public.chester_answer_admin('save',v,p_question=>'How do I prepare a show?',p_answer=>'Unreviewed changes',p_version=>2);
 if public.chester_match_answer('How do I prepare a show?')->>'answer'<>'Reviewed steps' then raise exception 'FAIL draft replaced live'; end if;
 begin perform public.chester_answer_admin('save',v,p_question=>'How do I prepare a show?',p_answer=>'Stale edit',p_version=>2); raise exception 'FAIL stale edit'; exception when others then if sqlerrm='FAIL stale edit' then raise; end if; end;
 begin perform public.chester_answer_admin('publish',v,p_question=>'Is my entry submitted?',p_answer=>'Yes',p_version=>3,p_reviewed=>true); raise exception 'FAIL status published'; exception when others then if sqlerrm='FAIL status published' then raise; end if; end;
 d:=public.chester_answer_admin('unpublish',v,p_version=>3);
 if public.chester_match_answer('How do I prepare a show?') is not null then raise exception 'FAIL unpublish'; end if;
end $$;
select set_config('request.jwt.claim.sub','94000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin perform public.chester_answer_admin('list'); raise exception 'FAIL user admin'; exception when others then if sqlerrm='FAIL user admin' then raise; end if; end;
 begin perform * from assistant_private.answers; raise exception 'FAIL private drafts'; exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
 begin perform public.chester_match_answer('How do I prepare a show?'); raise exception 'FAIL anon'; exception when insufficient_privilege then null; end;
end $$;
rollback;
