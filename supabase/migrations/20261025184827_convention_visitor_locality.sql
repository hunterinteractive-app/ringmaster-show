-- City/state are captured only after the buyer sees the updated location notice
-- and presses the purchase button. Neither raw coordinates nor provider payloads
-- are persisted. These records describe the check location, not a home address.
create table convention_sale_private.location_checks (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  email text not null,
  plan text not null check (plan in ('single_show','four_shows','unlimited')),
  sale_revision integer not null,
  venue text not null,
  checked_at timestamptz not null default now(),
  eligible boolean not null,
  city text check (length(city) between 1 and 150),
  state text check (state ~ '^[A-Z]{2}$'),
  locality_status text not null default 'pending'
    check (locality_status in ('pending','resolved','state_only','unavailable')),
  notice_version text not null default '2026-10-25-locality',
  check ((locality_status='resolved' and city is not null and state is not null)
    or (locality_status='state_only' and city is null and state is not null)
    or (locality_status in ('pending','unavailable') and city is null and state is null))
);
create index convention_location_user_time on convention_sale_private.location_checks(user_id,checked_at);
create index convention_location_time_id on convention_sale_private.location_checks(checked_at desc,id desc);
alter table convention_sale_private.location_checks enable row level security;
revoke all on convention_sale_private.location_checks from public,anon,authenticated;
grant select,insert,update on convention_sale_private.location_checks to service_role;

-- Service-only: authenticate the account in the Edge Function before calling.
create function public.convention_sale_location_check(
 p_id uuid,p_user_id uuid,p_email text,p_plan text,
 p_latitude double precision,p_longitude double precision,p_accuracy double precision,p_measured_at timestamptz
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare s convention_sale_private.settings%rowtype; c convention_sale_private.location_checks%rowtype;
 d double precision; radius_m double precision;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text,71526));
 select * into c from convention_sale_private.location_checks where id=p_id;
 if found then
   if c.user_id<>p_user_id or c.plan<>p_plan then raise exception 'Checkout request does not match'; end if;
   return to_jsonb(c)||jsonb_build_object('lookup_needed',false);
 end if;
 select * into s from convention_sale_private.settings where singleton;
 if not s.enabled or now()<s.starts_at or now()>=s.ends_at then
   raise exception 'The convention sale is not open';
 end if;
 if p_latitude is null or p_longitude is null or p_accuracy is null or p_measured_at is null
   or p_latitude not between -90 and 90 or p_longitude not between -180 and 180
   or p_accuracy not between 0 and 250
   or p_measured_at<now()-interval '60 seconds' or p_measured_at>now()+interval '30 seconds' then
   raise exception 'A fresh, accurate location reading is required. Retry or visit the booth for help.';
 end if;
 if (select count(*) from convention_sale_private.location_checks where user_id=p_user_id
   and checked_at>now()-interval '1 hour')>=30 then raise exception 'Too many checkout attempts. Try again later.'; end if;
 radius_m:=s.radius_miles*1609.344;
 d:=12742017.6*asin(sqrt(least(1,greatest(0,
   power(sin(radians(p_latitude-s.latitude)/2),2)
   +cos(radians(s.latitude))*cos(radians(p_latitude))*power(sin(radians(p_longitude-s.longitude)/2),2)))));
 insert into convention_sale_private.location_checks(id,user_id,email,plan,sale_revision,venue,eligible)
 values(p_id,p_user_id,p_email,p_plan,s.revision,s.venue,
   p_accuracy<=least(250,radius_m/2) and d+p_accuracy<=radius_m) returning * into c;
 return to_jsonb(c)||jsonb_build_object('lookup_needed',true);
end;
$$;
revoke all on function public.convention_sale_location_check(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz) from public,anon,authenticated;
grant execute on function public.convention_sale_location_check(uuid,uuid,text,text,double precision,double precision,double precision,timestamptz) to service_role;

create function public.convention_sale_location_result(
 p_id uuid,p_user_id uuid,p_city text,p_state text,p_status text
) returns void language sql security invoker set search_path='' as $$
 update convention_sale_private.location_checks set city=nullif(trim(p_city),''),state=p_state,locality_status=p_status
 where id=p_id and user_id=p_user_id and locality_status='pending';
$$;
revoke all on function public.convention_sale_location_result(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.convention_sale_location_result(uuid,uuid,text,text,text) to service_role;

-- Only Super Admin may read visitor records. Use a bounded, indexed cursor so
-- next year's sale does not replace history or require loading all visitors.
create function public.convention_sale_visitors(p_before timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.is_super_admin(auth.uid()) then
   raise exception 'Super Admin access required' using errcode='42501';
 end if;
 select coalesce(jsonb_agg(to_jsonb(v) order by v.checked_at desc,v.id desc),'[]'::jsonb) into result
 from (
   select l.id,l.email,l.plan,l.venue,l.checked_at,l.eligible,l.city,l.state,l.locality_status,
     c.fulfilled_at is not null as purchased
   from convention_sale_private.location_checks l
   left join convention_sale_private.claims c on c.id=l.id and c.user_id=l.user_id
   where p_before is null or (l.checked_at,l.id)<(p_before,p_before_id)
   order by l.checked_at desc,l.id desc limit 50
 ) v;
 return result;
end;
$$;
revoke all on function public.convention_sale_visitors(timestamptz,uuid) from public,anon;
grant execute on function public.convention_sale_visitors(timestamptz,uuid) to authenticated;
