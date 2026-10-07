-- Read-only domain access; only the separate metering system writes records.
create schema assistant_private;
revoke all on schema assistant_private from public, anon, authenticated;
grant usage on schema assistant_private to authenticated, service_role;
create table assistant_private.settings (
 id boolean primary key default true check(id),
 enabled boolean not null default false,
 monthly_budget_microusd bigint not null default 25000000 check(monthly_budget_microusd between 0 and 1000000000),
 daily_questions integer not null default 20 check(daily_questions between 1 and 200),
 minute_questions integer not null default 3 check(minute_questions between 1 and 10)
);
insert into assistant_private.settings(id) values(true);
create table assistant_private.usage (
 request_id uuid primary key,
 conversation_id uuid not null,
 -- Keep spending history even if an account is deleted; do not refund budget.
 actor_id uuid not null,
 created_at timestamptz not null default now(),
 topic text not null,
 model text not null default 'gpt-5.4-mini',
 state text not null default 'reserved' check(state in ('reserved','completed','failed')),
 charged_microusd bigint not null default 60000 check(charged_microusd>=0),
 input_tokens bigint not null default 0 check(input_tokens>=0),
 output_tokens bigint not null default 0 check(output_tokens>=0),
 calls integer not null default 0,
 finished_at timestamptz
);
create index assistant_usage_actor_time on assistant_private.usage(actor_id,created_at desc);
create index assistant_usage_time on assistant_private.usage(created_at);
alter table assistant_private.settings enable row level security;
alter table assistant_private.usage enable row level security;
revoke all on all tables in schema assistant_private from public,anon,authenticated,service_role;

-- Service-only metering API. The Edge Function derives actor_id from getUser,
-- never from the body. Serialize reservation and settlement on one settings row.
create function assistant_private.reserve(p_actor uuid,p_request uuid,p_conversation uuid,p_topic text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v assistant_private.settings; v_used bigint; v_now timestamptz:=now();
begin
 select * into v from assistant_private.settings where id for update;
 if not v.enabled then return jsonb_build_object('allowed',false,'reason','paused'); end if;
 if p_actor is null or p_request is null or p_conversation is null or p_topic not in ('help','entries','reports','household','setup','closeout') then
  raise exception 'Invalid assistant request';
 end if;
 if exists(select 1 from assistant_private.usage where request_id=p_request) then
  return jsonb_build_object('allowed',false,'reason','duplicate');
 end if;
 if exists(select 1 from assistant_private.usage where actor_id=p_actor and state='reserved' and created_at>v_now-interval '2 minutes') then
  return jsonb_build_object('allowed',false,'reason','busy');
 end if;
 if (select count(*) from assistant_private.usage where actor_id=p_actor and created_at>v_now-interval '1 minute')>=v.minute_questions then
  return jsonb_build_object('allowed',false,'reason','rate_limit');
 end if;
 if (select count(*) from assistant_private.usage where actor_id=p_actor and created_at>=date_trunc('day',v_now at time zone 'UTC') at time zone 'UTC')>=v.daily_questions then
  return jsonb_build_object('allowed',false,'reason','daily_limit');
 end if;
 select coalesce(sum(charged_microusd),0) into v_used from assistant_private.usage
 where created_at>=date_trunc('month',v_now at time zone 'UTC') at time zone 'UTC';
 if v_used+60000>v.monthly_budget_microusd then
  return jsonb_build_object('allowed',false,'reason','budget');
 end if;
 insert into assistant_private.usage(request_id,conversation_id,actor_id,topic)
 values(p_request,p_conversation,p_actor,p_topic);
 return jsonb_build_object('allowed',true);
end $$;
create function public.assistant_reserve(p_actor uuid,p_request uuid,p_conversation uuid,p_topic text)
returns jsonb language sql security invoker set search_path='' as $$
 select assistant_private.reserve(p_actor,p_request,p_conversation,p_topic);
$$;
create function assistant_private.finish(p_request uuid,p_input bigint,p_output bigint,p_calls integer,p_complete boolean)
returns void language plpgsql security definer set search_path='' as $$
declare v_cost bigint;
begin
 perform 1 from assistant_private.settings where id for update;
 if p_input<0 or p_output<0 or p_calls not between 0 and 2 then raise exception 'Invalid usage'; end if;
 -- No cache discounts assumed. All reasoning tokens are included in output.
 v_cost:=ceil(p_input*0.75+p_output*4.5);
 update assistant_private.usage set input_tokens=p_input,output_tokens=p_output,calls=p_calls,
  charged_microusd=case when p_complete then v_cost else greatest(charged_microusd,v_cost) end,
  state=case when p_complete then 'completed' else 'failed' end,finished_at=now()
 where request_id=p_request and state='reserved';
 if v_cost>60000 then update assistant_private.settings set enabled=false where id; end if;
 -- Unknown provider outcome/crash keeps the full reservation indefinitely.
end $$;
create function public.assistant_finish(p_request uuid,p_input bigint,p_output bigint,p_calls integer,p_complete boolean)
returns void language sql security invoker set search_path='' as $$
 select assistant_private.finish(p_request,p_input,p_output,p_calls,p_complete);
$$;
revoke all on function assistant_private.reserve(uuid,uuid,uuid,text), assistant_private.finish(uuid,bigint,bigint,integer,boolean),
 public.assistant_reserve(uuid,uuid,uuid,text),public.assistant_finish(uuid,bigint,bigint,integer,boolean) from public,anon,authenticated;
grant execute on function assistant_private.reserve(uuid,uuid,uuid,text), assistant_private.finish(uuid,bigint,bigint,integer,boolean),
 public.assistant_reserve(uuid,uuid,uuid,text),public.assistant_finish(uuid,bigint,bigint,integer,boolean) to service_role;

create function assistant_private.admin(p_enabled boolean default null,p_budget bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
 if auth.uid() is null or not public.is_super_admin(auth.uid()) then raise exception 'Not authorized'; end if;
 if p_enabled is not null or p_budget is not null then
  update assistant_private.settings set enabled=coalesce(p_enabled,enabled),monthly_budget_microusd=coalesce(p_budget,monthly_budget_microusd) where id;
 end if;
 select jsonb_build_object('settings',to_jsonb(s),'usage',(
  select jsonb_build_object('questions',count(*),'conversations',count(distinct conversation_id),
   'charged_microusd',coalesce(sum(charged_microusd),0),'input_tokens',coalesce(sum(input_tokens),0),
   'output_tokens',coalesce(sum(output_tokens),0),'unconfirmed',count(*) filter(where state<>'completed'))
  from assistant_private.usage where created_at>=date_trunc('month',now() at time zone 'UTC') at time zone 'UTC'),
  'recent_conversations',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from (
   select conversation_id,count(*) questions,sum(charged_microusd) charged_microusd,max(created_at) last_used
   from assistant_private.usage group by conversation_id order by max(created_at) desc limit 30) t)) into v_result
 from assistant_private.settings s where id;
 return v_result;
end $$;
create function public.assistant_admin(p_enabled boolean default null,p_budget bigint default null)
returns jsonb language sql security invoker set search_path='' as $$ select assistant_private.admin(p_enabled,p_budget); $$;
revoke all on function assistant_private.admin(boolean,bigint),public.assistant_admin(boolean,bigint) from public,anon;
grant execute on function assistant_private.admin(boolean,bigint),public.assistant_admin(boolean,bigint) to authenticated;

-- These read functions retain RLS AND add purpose/household constraints. No
-- support impersonation or arbitrary exhibitor/user lookup is available.
create function public.assistant_show_options(p_search text default '') returns jsonb
language sql stable security invoker set search_path='' set statement_timeout='3s' as $$
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from (
  select id,left(name,100) name,start_date from public.shows
  where auth.uid() is not null and name ilike '%'||left(p_search,80)||'%'
  order by start_date desc,id limit 25
 ) t;
$$;
create function public.assistant_read_context(p_topic text,p_owner uuid default null,p_show uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' set statement_timeout='3s' as $$
declare v_owner uuid:=coalesce(p_owner,auth.uid()); v_rows jsonb; v_show jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_topic not in ('entries','reports','household','setup','closeout') then raise exception 'Unsupported lookup'; end if;
 if p_topic in ('entries','reports','household') and not public.can_access_household(v_owner) then raise exception 'Household unavailable'; end if;
 if p_topic<>'household' and p_show is null then return jsonb_build_object('needs_show',true); end if;
 if p_topic in ('setup','closeout') and not public.user_can_manage_show_settings(p_show,auth.uid()) then raise exception 'Show unavailable'; end if;
 if p_topic<>'household' then
  select jsonb_build_object('name',left(s.name,100),'start_date',s.start_date,'end_date',s.end_date,
   'entry_close_at',s.entry_close_at,'is_published',s.is_published,'is_locked',s.is_locked) into v_show
  from public.shows s where s.id=p_show;
  if v_show is null then raise exception 'Show unavailable'; end if;
 end if;
 if p_topic='entries' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select left(e.tattoo,60) tattoo,left(e.breed,80) breed,left(e.class_name,60) class_name,e.status,
    left(x.showing_name,80) exhibitor,left(ss.display_name,80) section,e.created_at
   from public.entries e left join public.exhibitors x on x.id=e.exhibitor_id
   left join public.show_sections ss on ss.id=e.section_id
   where e.show_id=p_show and (e.exhibitor_user_id=v_owner or x.owner_user_id=v_owner)
   order by e.created_at desc,e.id limit 31
  ) t;
 elsif p_topic='reports' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select left(report_label,80) report,left(exhibitor_name,80) exhibitor,generated_at,legs_count
   from public.household_exhibitor_past_show_reports(v_owner) where show_id=p_show
   order by generated_at desc,artifact_id limit 31
  ) t;
 elsif p_topic='household' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select left(showing_name,80) showing_name,left(display_name,80) display_name,type,is_active
   from public.exhibitors where owner_user_id=v_owner order by id limit 31
  ) t;
 elsif p_topic='setup' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select left(display_name,80) name,kind,letter,judging_date,breed_scope,is_enabled
   from public.show_sections where show_id=p_show order by sort_order,id limit 31
  ) t;
 elsif p_topic='closeout' then
  -- Aggregate only: never include report bodies, recipient details or paths.
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select report_name,artifact_status,count(*) report_count
   from public.show_report_artifacts where show_id=p_show and is_current
   group by report_name,artifact_status order by report_name,artifact_status limit 31
  ) t;
 end if;
 return jsonb_build_object('topic',p_topic,'show',v_show,'rows',v_rows,
  'possibly_truncated',jsonb_array_length(v_rows)>=31,'checked_at',now());
end $$;
revoke all on function public.assistant_show_options(text),public.assistant_read_context(text,uuid,uuid) from public,anon;
grant execute on function public.assistant_show_options(text),public.assistant_read_context(text,uuid,uuid) to authenticated;
