create table assistant_private.conversations (
 id uuid primary key,
 actor_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table assistant_private.messages (
 id uuid primary key,
 conversation_id uuid not null references assistant_private.conversations(id) on delete cascade,
 ordinal integer not null check (ordinal >= 0),
 role text not null check (role in ('user','assistant','event')),
 content text not null check (length(content) between 1 and 32000),
 page text not null check (length(page)<=300),
 topic text not null check (length(topic)<=100),
 source text not null check (source in ('chat','prepared','ai','faq','support','error')),
 created_at timestamptz not null default now(),
 unique(conversation_id,ordinal)
);
create index chester_conversations_recent on assistant_private.conversations(updated_at desc,id);
create index chester_conversations_actor on assistant_private.conversations(actor_id);
alter table assistant_private.conversations enable row level security;
alter table assistant_private.messages enable row level security;
revoke all on assistant_private.conversations, assistant_private.messages from public,anon,authenticated;

-- Authenticated, append-only client transcript. Identity comes from the JWT,
-- never the payload. This records displayed chat, not an authoritative AI audit.
create function assistant_private.append_message(p_conversation uuid,p_id uuid,p_ordinal integer,p_role text,p_content text,p_page text,p_topic text,p_source text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Not authorized'; end if;
 insert into assistant_private.conversations(id,actor_id) values(p_conversation,auth.uid()) on conflict do nothing;
 perform 1 from assistant_private.conversations where id=p_conversation and actor_id=auth.uid() for update;
 if not found then raise exception 'Not authorized'; end if;
 if (select count(*) from assistant_private.messages m join assistant_private.conversations c on c.id=m.conversation_id where c.actor_id=auth.uid() and m.created_at>now()-interval '1 day') >= 2000 then raise exception 'Daily transcript limit reached'; end if;
 insert into assistant_private.messages(id,conversation_id,ordinal,role,content,page,topic,source)
 values(p_id,p_conversation,p_ordinal,p_role,p_content,p_page,p_topic,p_source) on conflict do nothing;
 update assistant_private.conversations set updated_at=now() where id=p_conversation;
end $$;
create function public.chester_append(p_conversation uuid,p_id uuid,p_ordinal integer,p_role text,p_content text,p_page text,p_topic text,p_source text)
returns void language sql security invoker set search_path='' as $$
 select assistant_private.append_message(p_conversation,p_id,p_ordinal,p_role,p_content,p_page,p_topic,p_source);
$$;
create function assistant_private.review(p_conversation uuid default null,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.is_super_admin(auth.uid()) then raise exception 'Not authorized'; end if;
 if p_conversation is null then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
   select c.*,u.email,(select left(m.content,160) from assistant_private.messages m where m.conversation_id=c.id order by ordinal limit 1) as preview,
   (select count(*) from assistant_private.messages m where m.conversation_id=c.id) as message_count
   from assistant_private.conversations c left join auth.users u on u.id=c.actor_id
   order by c.updated_at desc,c.id limit 50 offset greatest(0,least(coalesce(p_offset,0),100000))
  ) t;
 else
  select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
   select * from assistant_private.messages where conversation_id=p_conversation order by ordinal limit 100 offset greatest(0,least(coalesce(p_offset,0),100000))
  ) t;
 end if;
 return result;
end $$;
create function public.chester_review(p_conversation uuid default null,p_offset integer default 0)
returns jsonb language sql security invoker set search_path='' as $$ select assistant_private.review(p_conversation,p_offset); $$;
revoke all on function assistant_private.append_message(uuid,uuid,integer,text,text,text,text,text),public.chester_append(uuid,uuid,integer,text,text,text,text,text),assistant_private.review(uuid,integer),public.chester_review(uuid,integer) from public,anon;
grant usage on schema assistant_private to authenticated;
grant execute on function assistant_private.append_message(uuid,uuid,integer,text,text,text,text,text),public.chester_append(uuid,uuid,integer,text,text,text,text,text),assistant_private.review(uuid,integer),public.chester_review(uuid,integer) to authenticated;
