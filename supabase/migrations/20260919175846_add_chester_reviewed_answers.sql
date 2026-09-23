create table assistant_private.answers (
 id uuid primary key default gen_random_uuid(),
 source_message uuid references assistant_private.messages(id) on delete set null,
 question text not null,
 answer text not null,
 aliases text[] not null default '{}',
 version integer not null default 1,
 created_by uuid not null,
 updated_at timestamptz not null default now(),
 published_at timestamptz,
 reviewed_by uuid,
 published_answer text,
 check(length(question) between 1 and 300),
 check(length(answer) between 1 and 16000),
 check(cardinality(aliases) between 0 and 20)
);
create table assistant_private.answer_matches (
 question text primary key,
 answer_id uuid not null references assistant_private.answers(id) on delete cascade
);
create index chester_answer_matches_id on assistant_private.answer_matches(answer_id);
create index chester_answers_source on assistant_private.answers(source_message);
alter table assistant_private.answers enable row level security;
alter table assistant_private.answer_matches enable row level security;
revoke all on assistant_private.answers, assistant_private.answer_matches from public,anon,authenticated;
create function assistant_private.normalize_question(q text) returns text language sql immutable set search_path='' as $$
 select regexp_replace(regexp_replace(lower(trim(replace(q,'’',''''))),'[?!.]+$','','g'),'\s+',' ','g');
$$;
create function assistant_private.answer_admin(p_action text,p_id uuid default null,p_source uuid default null,p_question text default null,p_answer text default null,p_aliases text[] default null,p_version integer default null,p_reviewed boolean default false,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v assistant_private.answers; m assistant_private.messages; q text; result jsonb;
begin
 if auth.uid() is null or not public.is_super_admin(auth.uid()) then raise exception 'Super Admin access required'; end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (select * from assistant_private.answers order by updated_at desc,id limit 50 offset greatest(coalesce(p_offset,0),0)) t;
  return result;
 elsif p_action='create' then
  select * into m from assistant_private.messages where id=p_source and role='assistant';
  if not found then raise exception 'Select a Chester reply'; end if;
  select content into q from assistant_private.messages where conversation_id=m.conversation_id and role='user' and ordinal<m.ordinal order by ordinal desc limit 1;
  -- Remove obvious identifiers; a human must still remove names and private facts.
  q:=left(coalesce(q,'How do I use this feature?'),300);
  insert into assistant_private.answers(source_message,question,answer,created_by)
  values(m.id,regexp_replace(q,'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}','[email removed]','g'),
   regexp_replace(regexp_replace(m.content,'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}','[email removed]','g'),'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}','[ID removed]','g'),auth.uid()) returning * into v;
  return to_jsonb(v);
 end if;
 select * into v from assistant_private.answers where id=p_id for update;
 if not found then raise exception 'Draft not found'; end if;
 if p_version is distinct from v.version then raise exception 'This answer changed. Reload before saving.'; end if;
 if p_action='unpublish' then
  delete from assistant_private.answer_matches where answer_id=p_id;
  update assistant_private.answers set published_at=null,published_answer=null,reviewed_by=null,version=version+1,updated_at=now() where id=p_id returning * into v;
 elsif p_action in ('save','publish') then
  if p_question is null or p_answer is null or length(trim(p_question))=0 or length(trim(p_answer))=0 then raise exception 'Question and answer are required'; end if;
  update assistant_private.answers set question=trim(p_question),answer=trim(p_answer),aliases=coalesce(p_aliases,'{}'),version=version+1,updated_at=now() where id=p_id returning * into v;
  if p_action='publish' then
   if p_reviewed is distinct from true then raise exception 'Review privacy and steps before publishing'; end if;
   delete from assistant_private.answer_matches where answer_id=p_id;
   for q in select distinct assistant_private.normalize_question(x) from unnest(array[v.question]||v.aliases) x loop
    if length(q)>300 or q !~ '^(how (do|can|to) |where (can|do) |what (are the steps|should) )' then raise exception 'Matching questions must be general how-to questions, not personal status checks.'; end if;
    insert into assistant_private.answer_matches(question,answer_id) values(q,p_id);
   end loop;
   update assistant_private.answers set published_at=now(),reviewed_by=auth.uid(),published_answer=answer where id=p_id returning * into v;
  end if;
 else raise exception 'Unsupported action'; end if;
 return to_jsonb(v);
end $$;
create function public.chester_answer_admin(p_action text,p_id uuid default null,p_source uuid default null,p_question text default null,p_answer text default null,p_aliases text[] default null,p_version integer default null,p_reviewed boolean default false,p_offset integer default 0)
returns jsonb language sql security invoker set search_path='' as $$ select assistant_private.answer_admin(p_action,p_id,p_source,p_question,p_answer,p_aliases,p_version,p_reviewed,p_offset); $$;
create function assistant_private.match_answer(p_question text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if length(p_question)>1800 then return null; end if;
 select jsonb_build_object('id',a.id,'answer',a.published_answer) into result from assistant_private.answer_matches m join assistant_private.answers a on a.id=m.answer_id where m.question=assistant_private.normalize_question(p_question) and a.published_at is not null;
 return result;
end $$;
create function public.chester_match_answer(p_question text) returns jsonb language sql stable security invoker set search_path='' as $$ select assistant_private.match_answer(p_question); $$;
revoke all on function assistant_private.normalize_question(text),assistant_private.answer_admin(text,uuid,uuid,text,text,text[],integer,boolean,integer),public.chester_answer_admin(text,uuid,uuid,text,text,text[],integer,boolean,integer),assistant_private.match_answer(text),public.chester_match_answer(text) from public,anon,authenticated;
grant execute on function assistant_private.answer_admin(text,uuid,uuid,text,text,text[],integer,boolean,integer),public.chester_answer_admin(text,uuid,uuid,text,text,text[],integer,boolean,integer),assistant_private.match_answer(text),public.chester_match_answer(text) to authenticated;
