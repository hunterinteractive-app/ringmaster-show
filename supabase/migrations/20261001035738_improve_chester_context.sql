-- Extend only authorized household reads; retain invoker/RLS and budget limits.
create or replace function assistant_private.reserve(p_actor uuid,p_request uuid,p_conversation uuid,p_topic text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v assistant_private.settings; v_used bigint; v_now timestamptz:=now();
begin
 select * into v from assistant_private.settings where id for update;
 if not v.enabled then return jsonb_build_object('allowed',false,'reason','paused'); end if;
 if p_actor is null or p_request is null or p_conversation is null or p_topic not in ('help','entries','animals','reports','household','setup','closeout') then
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

create or replace function public.assistant_read_context(p_topic text,p_owner uuid default null,p_show uuid default null)
returns jsonb language plpgsql stable security invoker set search_path='' set statement_timeout='3s' as $$
declare v_owner uuid:=coalesce(p_owner,auth.uid()); v_rows jsonb; v_show jsonb; v_sections jsonb:='[]'::jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_topic not in ('entries','animals','reports','household','setup','closeout') then raise exception 'Unsupported lookup'; end if;
 if p_topic in ('entries','animals','reports','household') and not public.can_access_household(v_owner) then raise exception 'Household unavailable'; end if;
 if p_topic not in ('household','animals') and p_show is null then return jsonb_build_object('needs_show',true); end if;
 if p_topic in ('setup','closeout') and not public.user_can_manage_show_settings(p_show,auth.uid()) then raise exception 'Show unavailable'; end if;
 if p_topic not in ('household','animals') then
  select jsonb_build_object('name',left(s.name,100),'start_date',s.start_date,'end_date',s.end_date,
   'entry_close_at',s.entry_close_at,'is_published',s.is_published,'is_locked',s.is_locked) into v_show
  from public.shows s where s.id=p_show;
  if v_show is null then raise exception 'Show unavailable'; end if;
 end if;
 if p_topic='entries' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_sections from (
   select left(display_name,80) name,kind,letter,breed_scope,is_enabled
   from public.show_sections where show_id=p_show order by sort_order,id limit 31
  ) t;
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select left(e.tattoo,60) tattoo,left(e.breed,80) breed,left(e.class_name,60) class_name,e.status,
    left(x.showing_name,80) exhibitor,left(ss.display_name,80) section,e.created_at
   from public.entries e left join public.exhibitors x on x.id=e.exhibitor_id
   left join public.show_sections ss on ss.id=e.section_id
   where e.show_id=p_show and (e.exhibitor_user_id=v_owner or x.owner_user_id=v_owner)
   order by e.created_at desc,e.id limit 31
  ) t;
 elsif p_topic='animals' then
  select coalesce(jsonb_agg(to_jsonb(t)),'[]') into v_rows from (
   select left(a.name,80) name,left(a.tattoo,60) tattoo,left(a.breed,80) breed,
    left(a.variety,80) variety,a.sex,a.species,a.birth_date,a.is_dob_unknown
   from public.animals a
   where a.owner_user_id=v_owner and a.deleted_at is null
   order by a.created_at desc,a.id limit 31
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
  'sections',v_sections,'sections_possibly_truncated',jsonb_array_length(v_sections)>=31,
  'possibly_truncated',jsonb_array_length(v_rows)>=31,'checked_at',now());
end $$;
revoke all on function public.assistant_show_options(text),public.assistant_read_context(text,uuid,uuid) from public,anon;
grant execute on function public.assistant_show_options(text),public.assistant_read_context(text,uuid,uuid) to authenticated;
