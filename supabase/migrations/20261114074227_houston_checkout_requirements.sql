-- Houston's checkout questions and affirmative agreement. Other shows retain
-- their existing checkout behavior. Acceptance is never inferred from payment.
create schema if not exists show_registration_private;
revoke all on schema show_registration_private from public, anon, authenticated;
grant usage on schema show_registration_private to authenticated, service_role;

create table show_registration_private.policies (
  owner_user_id uuid not null,
  club_id uuid not null,
  version text not null,
  agreement text not null,
  handbook_url text not null,
  website_url text not null,
  primary key(owner_user_id,club_id)
);
create table show_registration_private.schools (
  cart_id uuid not null references public.entry_carts(id),
  exhibitor_id uuid not null references public.exhibitors(id),
  school_name text not null check(length(btrim(school_name)) between 1 and 200),
  city text not null check(length(btrim(city)) between 1 and 120),
  state text not null check(state ~ '^[A-Z]{2}$'),
  updated_at timestamptz not null default now(),
  primary key(cart_id,exhibitor_id)
);
create index on show_registration_private.schools(exhibitor_id);
create table show_registration_private.acceptances (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.entry_carts(id),
  accepted_by uuid not null,
  accepted_at timestamptz not null default now(),
  version text not null,
  agreement text not null,
  handbook_url text not null,
  website_url text not null,
  cart_signature text not null,
  school_snapshot jsonb not null
);
create index on show_registration_private.acceptances(cart_id,accepted_at desc);
alter table show_registration_private.policies enable row level security;
alter table show_registration_private.schools enable row level security;
alter table show_registration_private.acceptances enable row level security;
revoke all on all tables in schema show_registration_private from public,anon,authenticated;

insert into show_registration_private.policies values (
  'bca983ed-59ac-4615-a9a7-a2ce56d3d8e8', '48522136-118e-4860-aa46-1abb2d783809',
  'hlsr-2027-handbook-v2',
  'I agree to the Houston Livestock Show and Rodeo rules listed in the 2027 Exhibitor Handbook and all terms and conditions listed on the Houston Livestock Show and Rodeo website.',
  'https://www.rodeohouston.com/wp-content/uploads/2026/10/2027-Exhibitor-Handbook-V2.pdf',
  'https://www.rodeohouston.com'
);

create function show_registration_private.policy(p_show uuid)
returns setof show_registration_private.policies language sql stable set search_path='' as $$
  select p.* from show_registration_private.policies p join public.shows s
    on s.owner_user_id=p.owner_user_id and s.club_id=p.club_id where s.id=p_show;
$$;

create function show_registration_private.youth_exhibitors(p_cart uuid)
returns table(exhibitor_id uuid) language sql stable set search_path='' as $$
  select distinct i.exhibitor_id from public.entry_cart_items i
    join public.show_sections s on s.id=i.section_id
    where i.cart_id=p_cart and lower(s.kind::text)='youth'
      and not i.is_checkin_fee_carrier and i.exhibitor_id is not null
  union
  select r.exhibitor_id from show_addons_private.selections r
    where r.cart_id=p_cart and r.kind='contest' and exists (
      select 1 from public.show_sections s where s.show_id=r.show_id and lower(s.kind::text)='youth'
    ) and not exists (
      select 1 from public.show_sections s where s.show_id=r.show_id and lower(s.kind::text)='open'
    );
$$;

create function show_registration_private.cart_signature(p_cart uuid)
returns text language sql stable set search_path='' as $$
  select md5(jsonb_build_object(
    'cart',p_cart,
    'entries',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.entry_cart_items i
      where i.cart_id=p_cart and not i.is_checkin_fee_carrier),'[]'),
    'addons',coalesce((select jsonb_agg(to_jsonb(r) order by r.id) from show_addons_private.selections r where r.cart_id=p_cart),'[]'),
    'youth',coalesce((select jsonb_agg(exhibitor_id order by exhibitor_id) from show_registration_private.youth_exhibitors(p_cart)),'[]')
  )::text);
$$;

create function show_registration_private.requirements(p_cart_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; p show_registration_private.policies%rowtype; kids jsonb;
begin
  c:=show_addons_private.assert_cart(p_cart_id);
  select * into p from show_registration_private.policy(c.show_id);
  if not found then return jsonb_build_object('required',false); end if;
  select coalesce(jsonb_agg(jsonb_build_object('exhibitor_id',e.id,
    'name',coalesce(nullif(e.showing_name,''),e.display_name),'number',e.exhibitor_number,
    'school_name',coalesce(sc.school_name,''),'city',coalesce(sc.city,''),'state',coalesce(sc.state,'TX'))
    order by e.exhibitor_number,e.id),'[]') into kids
  from show_registration_private.youth_exhibitors(c.id) y join public.exhibitors e on e.id=y.exhibitor_id
  left join lateral (
    select x.* from show_registration_private.schools x join public.entry_carts old on old.id=x.cart_id
    where x.exhibitor_id=e.id and old.user_id=c.user_id and old.show_id=c.show_id
    order by (x.cart_id=c.id) desc,x.updated_at desc limit 1
  ) sc on true;
  return jsonb_build_object('required',true,'version',p.version,'agreement',p.agreement,
    'handbook_url',p.handbook_url,'website_url',p.website_url,'exhibitors',kids);
end; $$;

create function show_registration_private.save_requirements(p_cart_id uuid,p_version text,p_agreed boolean,p_schools jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; p show_registration_private.policies%rowtype; ex uuid; x jsonb; snapshot jsonb;
begin
  -- School/consent records do not change charges. A retry of an existing
  -- payment attempt or payment of a submitted cart can record them too.
  c:=show_addons_private.assert_cart(p_cart_id);
  if c.status not in ('active','submitted') then raise exception 'This cart is no longer available for checkout.'; end if;
  select * into p from show_registration_private.policy(c.show_id);
  if not found then return; end if;
  if p_agreed is distinct from true or p_version is distinct from p.version then
    raise exception 'Agree to the Houston Livestock Show and Rodeo rules and terms before checkout.';
  end if;
  if jsonb_typeof(p_schools) is distinct from 'array' or jsonb_array_length(p_schools)>1000 then raise exception 'Invalid school information.'; end if;
  if exists(select 1 from jsonb_array_elements(p_schools) s where not exists(
    select 1 from show_registration_private.youth_exhibitors(c.id) y where y.exhibitor_id::text=s->>'exhibitor_id')) then
    raise exception 'School information must belong to a youth exhibitor in this cart.' using errcode='42501';
  end if;
  for ex in select exhibitor_id from show_registration_private.youth_exhibitors(c.id) loop
    if (select count(*) from jsonb_array_elements(p_schools) s where s->>'exhibitor_id'=ex::text)<>1 then
      raise exception 'Enter school name, city, and state for every youth exhibitor.';
    end if;
    select value into x from jsonb_array_elements(p_schools) where value->>'exhibitor_id'=ex::text;
    if coalesce(length(btrim(x->>'school_name')),0) not between 1 and 200
      or coalesce(length(btrim(x->>'city')),0) not between 1 and 120
      or coalesce(upper(btrim(x->>'state')),'') !~ '^[A-Z]{2}$' then
      raise exception 'Enter school name, city, and a two-letter state for every youth exhibitor.';
    end if;
    insert into show_registration_private.schools(cart_id,exhibitor_id,school_name,city,state)
    values(c.id,ex,btrim(x->>'school_name'),btrim(x->>'city'),upper(btrim(x->>'state')))
    on conflict(cart_id,exhibitor_id) do update set school_name=excluded.school_name,city=excluded.city,state=excluded.state,updated_at=now();
  end loop;
  select coalesce(jsonb_agg(to_jsonb(s) order by s.exhibitor_id),'[]') into snapshot
    from show_registration_private.schools s join show_registration_private.youth_exhibitors(c.id) y using(exhibitor_id) where s.cart_id=c.id;
  insert into show_registration_private.acceptances(cart_id,accepted_by,version,agreement,handbook_url,website_url,cart_signature,school_snapshot)
  values(c.id,auth.uid(),p.version,p.agreement,p.handbook_url,p.website_url,show_registration_private.cart_signature(c.id),snapshot);
end; $$;

create function show_registration_private.validate_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
declare p show_registration_private.policies%rowtype; c public.entry_carts%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart;
  select * into p from show_registration_private.policy(c.show_id);
  if not found then return; end if;
  if exists(select 1 from show_registration_private.youth_exhibitors(c.id) y where not exists(
    select 1 from show_registration_private.schools s where s.cart_id=c.id and s.exhibitor_id=y.exhibitor_id)) then
    raise exception 'Enter school name, city, and state for every youth exhibitor before checkout.';
  end if;
  if not exists(select 1 from show_registration_private.acceptances a where a.cart_id=c.id and a.version=p.version
      and a.cart_signature=show_registration_private.cart_signature(c.id)) then
    raise exception 'Review this cart and agree to the Houston Livestock Show and Rodeo rules and terms before checkout.';
  end if;
end; $$;

create function public.get_cart_registration_requirements(p_cart_id uuid)
returns jsonb language sql security invoker set search_path='' as $$select show_registration_private.requirements(p_cart_id);$$;
create function public.save_cart_registration_requirements(p_cart_id uuid,p_version text,p_agreed boolean,p_schools jsonb)
returns void language sql security invoker set search_path='' as $$select show_registration_private.save_requirements(p_cart_id,p_version,p_agreed,p_schools);$$;

-- Guard the start of online/offline/free checkout, not payment webhooks or
-- price previews. Existing pending payments retain their original lifecycle.
do $$declare sig text; d text; marker text:='  perform show_addons_private.validate_cart(p_cart_id);'; begin
  foreach sig in array array[
    'public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)',
    'public.commit_entry_cart_day_of(uuid)', 'public.commit_free_entry_cart(uuid)'
  ] loop
    d:=pg_get_functiondef(sig::regprocedure);
    if (length(d)-length(replace(d,marker,'')))/length(marker)<>1 then raise exception 'Checkout guard anchor changed: %',sig; end if;
    execute replace(d,marker,E'  perform show_registration_private.validate_cart(p_cart_id);\n'||marker);
  end loop;
end; $$;

revoke all on all functions in schema show_registration_private from public,anon,authenticated;
grant execute on function show_registration_private.requirements(uuid),show_registration_private.save_requirements(uuid,text,boolean,jsonb) to authenticated;
revoke all on function public.get_cart_registration_requirements(uuid),public.save_cart_registration_requirements(uuid,text,boolean,jsonb) from public,anon;
grant execute on function public.get_cart_registration_requirements(uuid),public.save_cart_registration_requirements(uuid,text,boolean,jsonb) to authenticated;
notify pgrst,'reload schema';
