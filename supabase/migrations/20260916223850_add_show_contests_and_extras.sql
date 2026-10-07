-- Optional, show-wide contests and merchandise. Registration identity is the
-- exhibitor, not an animal. Amounts and form snapshots are server-owned.
alter table public.shows add column contests_enabled boolean not null default false,
  add column extras_enabled boolean not null default false;
alter table public.entry_cart_items add column is_show_addon_carrier boolean not null default false;
alter table public.show_exhibitor_balances add column addons_subtotal_cents integer not null default 0;
create schema show_addons_private;
revoke all on schema show_addons_private from public,anon,authenticated;
grant usage on schema show_addons_private to authenticated,service_role;

create table show_addons_private.offerings (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  kind text not null check(kind in ('contest','extra')),
  name text not null check(length(btrim(name)) between 1 and 120),
  description text not null default '' check(length(description)<=4000),
  price_cents integer not null default 0 check(price_cents between 0 and 9999999),
  enabled boolean not null default true,
  requires_animal_entry boolean not null default false,
  divisions jsonb not null default '[]',
  animal_selection text not null default 'none' check(animal_selection in ('none','optional','required')),
  max_per_exhibitor integer not null default 1 check(max_per_exhibitor between 1 and 999),
  fields jsonb not null default '[]',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check(kind<>'contest' or max_per_exhibitor=1)
);
create index show_addon_offerings_show on show_addons_private.offerings(show_id,kind);
create table show_addons_private.selections (
  id uuid primary key default extensions.gen_random_uuid(),
  offering_id uuid not null references show_addons_private.offerings(id),
  show_id uuid not null references public.shows(id),
  cart_id uuid not null references public.entry_carts(id) on delete cascade,
  exhibitor_id uuid not null references public.exhibitors(id),
  carrier_id uuid not null unique references public.entry_cart_items(id) on delete cascade,
  quantity integer not null check(quantity between 1 and 999),
  unit_price_cents integer not null check(unit_price_cents between 0 and 9999999),
  name text not null, kind text not null, fields jsonb not null, answers jsonb not null,
  division text, animal_key text, animal_snapshot jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(cart_id,offering_id,exhibitor_id),
  check(quantity::bigint*unit_price_cents<=99999999)
);
create index show_addon_selections_offering_exhibitor on show_addons_private.selections(offering_id,exhibitor_id);
create index show_addon_selections_show on show_addons_private.selections(show_id);
create index show_addon_selections_exhibitor on show_addons_private.selections(exhibitor_id);
alter table show_addons_private.offerings enable row level security;
alter table show_addons_private.selections enable row level security;
create policy backend_only on show_addons_private.offerings for all to authenticated using(false) with check(false);
create policy backend_only on show_addons_private.selections for all to authenticated using(false) with check(false);
revoke all on all tables in schema show_addons_private from public,anon,authenticated;

create function show_addons_private.assert_secretary(p_show uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not public.user_can_manage_show_settings(p_show) then
    raise exception 'Only show secretaries and administrators can manage contests and add-ons.' using errcode='42501';
  end if;
  if exists(select 1 from public.shows where id=p_show and (is_locked or finalized_at is not null)) then
    raise exception 'This show is locked or finalized.';
  end if;
end;
$$;
create function show_addons_private.guard_enabled()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if (new.contests_enabled,new.extras_enabled) is distinct from (old.contests_enabled,old.extras_enabled) then
    perform show_addons_private.assert_secretary(old.id);
  end if;
  return new;
end;
$$;
create trigger guard_show_addons_enabled before update of contests_enabled,extras_enabled on public.shows
for each row execute function show_addons_private.guard_enabled();

create function show_addons_private.validate_fields(p_fields jsonb,p_answers jsonb default null)
returns void language plpgsql security invoker set search_path='' as $$
declare f jsonb; a jsonb; t text; ids text[]:=array[]::text[];
begin
  if jsonb_typeof(p_fields) is distinct from 'array' or jsonb_array_length(p_fields)>20 then raise exception 'Use at most 20 contest fields.'; end if;
  if p_answers is not null and (jsonb_typeof(p_answers)<>'object' or length(p_answers::text)>45000) then raise exception 'Invalid contest answers.'; end if;
  for f in select value from jsonb_array_elements(p_fields) loop
    if jsonb_typeof(f)<>'object' or coalesce(f->>'id','') !~ '^[a-zA-Z0-9_-]{1,64}$'
      or f->>'id'=any(ids) or length(btrim(coalesce(f->>'label',''))) not between 1 and 120
      or coalesce(f->>'type','') not in ('text','long_text','number','date','checkbox','select')
      or jsonb_typeof(f->'required') is distinct from 'boolean' then raise exception 'Each field needs a unique ID, label, type, and required setting.'; end if;
    ids:=array_append(ids,f->>'id');
    if f->>'type'='select' then
      if jsonb_typeof(f->'options') is distinct from 'array' or jsonb_array_length(f->'options') not between 1 and 100
        or exists(select 1 from jsonb_array_elements(f->'options') x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}')) not between 1 and 120)
        or (select count(distinct value)<>count(*) from jsonb_array_elements(f->'options')) then raise exception 'Dropdown choices must be unique, nonempty text.'; end if;
    end if;
    if p_answers is null then continue; end if;
    a:=p_answers->(f->>'id'); t:=btrim(coalesce(a#>>'{}',''));
    if (f->>'required')::boolean and (t='' or a='null'::jsonb or (f->>'type'='checkbox' and a is distinct from 'true'::jsonb)) then
      raise exception '% is required.',f->>'label';
    end if;
    if a is null or a='null'::jsonb or t='' then continue; end if;
    if length(t)>2000 or jsonb_typeof(a) not in ('string','number','boolean') then raise exception 'Invalid answer for %.',f->>'label'; end if;
    if f->>'type'='checkbox' and jsonb_typeof(a)<>'boolean' then raise exception '% must be a checkbox value.',f->>'label'; end if;
    if f->>'type'='number' and t !~ '^-?[0-9]+(\.[0-9]+)?$' then raise exception '% must be a number.',f->>'label'; end if;
    if f->>'type'='date' then
      if t !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char(t::date,'YYYY-MM-DD')<>t then raise exception '% must be a valid date.',f->>'label'; end if;
    end if;
    if f->>'type'='select' and not (f->'options' ? t) then raise exception 'Choose a valid option for %.',f->>'label'; end if;
  end loop;
  if p_answers is not null and exists(select 1 from jsonb_object_keys(p_answers) k where not k=any(ids)) then raise exception 'The form has changed. Reload it before continuing.'; end if;
end;
$$;

create function show_addons_private.catalog(p_show_id uuid,p_admin boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.shows%rowtype; items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in to view contests and add-ons.' using errcode='42501'; end if;
  select * into s from public.shows where id=p_show_id;
  if not found or (not coalesce(s.is_published,false) and not public.user_can_manage_show_settings(p_show_id)) then raise exception 'Show is unavailable.' using errcode='42501'; end if;
  if p_admin and not public.user_can_manage_show_settings(p_show_id) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(o) order by lower(o.name),o.id),'[]') into items from show_addons_private.offerings o
    where o.show_id=p_show_id and (p_admin or (o.enabled and case when o.kind='contest' then s.contests_enabled else s.extras_enabled end));
  return jsonb_build_object('contests_enabled',s.contests_enabled,'extras_enabled',s.extras_enabled,'items',items,
    'currency',coalesce((select lower(currency) from public.show_fee_settings where show_id=p_show_id),'usd'),
    'entry_open_at',s.entry_open_at,'entry_close_at',s.entry_close_at,'locked',coalesce(s.is_locked,false) or s.finalized_at is not null);
end;
$$;
create function show_addons_private.set_enabled(p_show_id uuid,p_kind text,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform show_addons_private.assert_secretary(p_show_id);
  if p_kind='contest' then update public.shows set contests_enabled=p_enabled where id=p_show_id;
  elsif p_kind='extra' then update public.shows set extras_enabled=p_enabled where id=p_show_id;
  else raise exception 'Unknown offering type.'; end if;
end;
$$;
create function show_addons_private.validate_contest_options(p_kind text,p_divisions jsonb,p_animal_selection text)
returns void language plpgsql security invoker set search_path='' as $$
begin
  if jsonb_typeof(p_divisions) is distinct from 'array' or jsonb_array_length(p_divisions)>100 then raise exception 'Use up to 100 contest divisions.'; end if;
  if exists(select 1 from jsonb_array_elements(p_divisions) x where jsonb_typeof(x)<>'string' or length(btrim(x#>>'{}')) not between 1 and 120)
    or (select count(distinct btrim(value#>>'{}'))<>count(*) from jsonb_array_elements(p_divisions)) then raise exception 'Divisions must be unique, nonempty names.'; end if;
  if p_animal_selection not in ('none','optional','required') then raise exception 'Invalid animal selection setting.'; end if;
  if p_kind<>'contest' and (p_divisions<>'[]'::jsonb or p_animal_selection<>'none') then raise exception 'Division and animal choices are only used for contests.'; end if;
end;
$$;
create function show_addons_private.save_offering(p_show_id uuid,p_item jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_item->>'id')::uuid; existing show_addons_private.offerings%rowtype;
begin
  perform show_addons_private.assert_secretary(p_show_id);
  perform show_addons_private.validate_fields(coalesce(p_item->'fields','[]'));
  perform show_addons_private.validate_contest_options(p_item->>'kind',coalesce(p_item->'divisions','[]'),coalesce(p_item->>'animal_selection','none'));
  select * into existing from show_addons_private.offerings where id=v_id for update;
  if found and (existing.show_id<>p_show_id or existing.kind<>p_item->>'kind') then raise exception 'This item belongs to a different show or type.' using errcode='42501'; end if;
  if p_item->>'kind'='extra' and jsonb_array_length(coalesce(p_item->'fields','[]'))>0 then raise exception 'Add-on items do not use contest fields.'; end if;
  insert into show_addons_private.offerings(id,show_id,kind,name,description,price_cents,enabled,requires_animal_entry,max_per_exhibitor,fields,divisions,animal_selection)
    values(v_id,p_show_id,p_item->>'kind',btrim(p_item->>'name'),coalesce(p_item->>'description',''),(p_item->>'price_cents')::integer,
      coalesce((p_item->>'enabled')::boolean,true),coalesce((p_item->>'requires_animal_entry')::boolean,false),
      case when p_item->>'kind'='contest' then 1 else coalesce((p_item->>'max_per_exhibitor')::integer,99) end,coalesce(p_item->'fields','[]'),
      coalesce((select jsonb_agg(btrim(value#>>'{}')) from jsonb_array_elements(coalesce(p_item->'divisions','[]'))),'[]'),coalesce(p_item->>'animal_selection','none'))
  on conflict(id) do update set name=excluded.name,description=excluded.description,price_cents=excluded.price_cents,
    enabled=excluded.enabled,requires_animal_entry=excluded.requires_animal_entry,max_per_exhibitor=excluded.max_per_exhibitor,
    fields=excluded.fields,divisions=excluded.divisions,animal_selection=excluded.animal_selection,updated_at=now()
    where offerings.show_id=p_show_id and offerings.kind=excluded.kind;
  if not found then raise exception 'This item belongs to a different show or type.' using errcode='42501'; end if;
  return v_id;
end;
$$;

create function show_addons_private.assert_cart(p_cart uuid,p_write boolean default false)
returns public.entry_carts language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart for update;
  if not found or auth.uid() is null or not household_private.has_access(c.user_id) then raise exception 'You do not have access to this cart.' using errcode='42501'; end if;
  if p_write and (c.status<>'active' or c.active_payment_session_id is not null or c.completed_payment_session_id is not null
    or c.payment_status in ('pending','paid','refunded') or exists(select 1 from public.show_exhibitor_balances b where b.entry_cart_id=p_cart
      and (b.paid_online_cents<>0 or b.paid_manual_cents<>0 or b.refunded_cents<>0))) then raise exception 'This cart is already submitted or has a payment in progress.'; end if;
  return c;
end;
$$;
create function show_addons_private.assert_eligible(p_cart public.entry_carts,p_offer show_addons_private.offerings,p_ex uuid)
returns void language plpgsql security definer set search_path='' as $$
declare s public.shows%rowtype;
begin
  select * into s from public.shows where id=p_cart.show_id;
  if p_offer.show_id<>s.id or not p_offer.enabled or not (case when p_offer.kind='contest' then s.contests_enabled else s.extras_enabled end)
    or not coalesce(s.is_published,false) then raise exception 'This contest or add-on is not available.'; end if;
  if coalesce(s.is_locked,false) or s.finalized_at is not null then raise exception 'This show is locked or finalized.'; end if;
  if s.entry_open_at>now() or s.entry_close_at<now() then raise exception 'Registration is outside this show’s entry window.'; end if;
  if not exists(select 1 from public.exhibitors e where e.id=p_ex and e.owner_user_id=p_cart.user_id and e.is_active) then
    raise exception 'Choose an active exhibitor from this household.' using errcode='42501'; end if;
  if p_offer.requires_animal_entry and not (
    exists(select 1 from public.entries e where e.show_id=s.id and e.exhibitor_id=p_ex and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled','withdrawn'))
    or exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart.id and i.exhibitor_id=p_ex and not i.is_checkin_fee_carrier and not coalesce(i.is_fur,false))) then
    raise exception '% requires an animal entry for this exhibitor in this show.',p_offer.name;
  end if;
end;
$$;
-- Logical animal keys keep animals entered in several sections in one picker.
-- The snapshot is server-owned and retained even if an entry is later removed.
create function show_addons_private.animal_choices(p_cart public.entry_carts,p_ex uuid)
returns jsonb language sql security invoker set search_path='' as $$
  with eligible as (
    select e.id,e.animal_id,e.species::text species,e.breed,e.tattoo,e.animal_name,'entry'::text source,0 priority
    from public.entries e where e.show_id=p_cart.show_id and e.exhibitor_id=p_ex and not coalesce(e.is_fur,false)
      and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled','canceled','withdrawn')
    union all
    select i.id,i.animal_id,i.species::text,i.breed,i.tattoo,i.animal_name,'cart',1
    from public.entry_cart_items i where i.cart_id=p_cart.id and i.exhibitor_id=p_ex
      and not i.is_checkin_fee_carrier and not coalesce(i.is_fur,false)
  ), keyed as (
    select *,case when animal_id is not null then 'animal:'||animal_id::text
      when nullif(btrim(tattoo),'') is not null then 'tag:'||md5(jsonb_build_array(lower(species),lower(btrim(breed)),btrim(tattoo))::text)
      else source||':'||id::text end animal_key from eligible
  ), unique_animals as (select distinct on (animal_key) * from keyed order by animal_key,priority,id)
  select coalesce(jsonb_agg(jsonb_build_object('key',animal_key,'source',source,'source_id',id,'animal_id',animal_id,
    'species',species,'breed',breed,'tattoo',tattoo,'animal_name',animal_name,
    'label',concat_ws(' • ',nullif(animal_name,''),initcap(species),nullif(breed,''),'Ear #: '||coalesce(nullif(tattoo,''),'—'))) order by lower(breed),tattoo,animal_key),'[]') from unique_animals;
$$;
create function show_addons_private.contest_animals(p_cart_id uuid,p_exhibitor_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype;
begin
  c:=show_addons_private.assert_cart(p_cart_id);
  if not exists(select 1 from public.exhibitors e where e.id=p_exhibitor_id and e.owner_user_id=c.user_id and e.is_active) then
    raise exception 'Choose an active exhibitor from this household.' using errcode='42501'; end if;
  return show_addons_private.animal_choices(c,p_exhibitor_id);
end;
$$;
create function show_addons_private.validate_choices(p_cart public.entry_carts,p_offer show_addons_private.offerings,p_ex uuid,p_division text,p_animal_key text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare snapshot jsonb;
begin
  if jsonb_array_length(p_offer.divisions)>0 then
    if p_division is null or not (p_offer.divisions ? p_division) then raise exception 'Choose a valid division for %.',p_offer.name; end if;
  elsif p_division is not null then raise exception 'This contest does not use divisions.'; end if;
  if p_offer.animal_selection='required' and p_animal_key is null then raise exception 'Choose an entered animal for %.',p_offer.name; end if;
  if p_animal_key is not null then
    if p_offer.animal_selection='none' then raise exception 'This contest does not use animal selection.'; end if;
    select value into snapshot from jsonb_array_elements(show_addons_private.animal_choices(p_cart,p_ex)) where value->>'key'=p_animal_key;
    if snapshot is null then raise exception 'Choose an eligible animal entered for this exhibitor in this show.'; end if;
  end if;
  return snapshot;
end;
$$;
create function show_addons_private.refresh_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  -- Only called after asserting an unpaid, mutable draft; zero-cost balance
  -- rows otherwise trip the legacy paid-balance protection during repricing.
  perform set_config('ringmaster.payment_state_write','on',true);
  delete from public.show_exhibitor_balances b where b.entry_cart_id=p_cart and b.source='cart'
    and not exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart and i.exhibitor_id=b.exhibitor_id);
  perform public.calculate_entry_cart_balance_internal(p_cart);
  perform set_config('ringmaster.payment_state_write','off',true);
end;
$$;
create function show_addons_private.save_selection(p_cart_id uuid,p_offering_id uuid,p_exhibitor_id uuid,p_quantity integer,p_answers jsonb,p_division text default null,p_animal_key text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; o show_addons_private.offerings%rowtype; r show_addons_private.selections%rowtype;
  carrier uuid; section uuid; used integer; animal jsonb;
begin
  c:=show_addons_private.assert_cart(p_cart_id,true);
  select * into o from show_addons_private.offerings where id=p_offering_id for update;
  if not found then raise exception 'Item not found.'; end if;
  perform show_addons_private.assert_eligible(c,o,p_exhibitor_id);
  perform show_addons_private.validate_fields(o.fields,p_answers);
  p_division:=nullif(btrim(p_division),''); p_animal_key:=nullif(btrim(p_animal_key),'');
  animal:=show_addons_private.validate_choices(c,o,p_exhibitor_id,p_division,p_animal_key);
  select coalesce(sum(selected.quantity),0) into used from show_addons_private.selections selected join public.entry_carts ec on ec.id=selected.cart_id
    where selected.offering_id=o.id and selected.exhibitor_id=p_exhibitor_id and selected.cart_id<>c.id and ec.status in ('active','submitted');
  if p_quantity is null or p_quantity<1 or p_quantity+used>o.max_per_exhibitor then raise exception 'The limit for % is % per exhibitor across the full show.',o.name,o.max_per_exhibitor; end if;
  select * into r from show_addons_private.selections where cart_id=c.id and offering_id=o.id and exhibitor_id=p_exhibitor_id;
  if found then carrier:=r.carrier_id;
  else
    select id into section from public.show_sections where show_id=c.show_id order by sort_order,id limit 1;
    if section is null then raise exception 'The secretary must set up at least one show section before accepting registrations.'; end if;
    insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,is_checkin_fee_carrier,is_show_addon_carrier)
      values(c.id,section,p_exhibitor_id,'rabbit','SHOW-ADDON',true,true) returning id into carrier;
  end if;
  insert into show_addons_private.selections(offering_id,show_id,cart_id,exhibitor_id,carrier_id,quantity,unit_price_cents,name,kind,fields,answers,division,animal_key,animal_snapshot)
    values(o.id,c.show_id,c.id,p_exhibitor_id,carrier,p_quantity,o.price_cents,o.name,o.kind,o.fields,p_answers,p_division,p_animal_key,animal)
    on conflict(cart_id,offering_id,exhibitor_id) do update set quantity=excluded.quantity,unit_price_cents=excluded.unit_price_cents,
      name=excluded.name,fields=excluded.fields,answers=excluded.answers,division=excluded.division,animal_key=excluded.animal_key,animal_snapshot=excluded.animal_snapshot,updated_at=now() returning id into r.id;
  perform show_addons_private.refresh_cart(c.id);
  return r.id;
end;
$$;
create function show_addons_private.remove_selection(p_selection_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r show_addons_private.selections%rowtype;
begin
  select * into r from show_addons_private.selections where id=p_selection_id;
  if not found then return; end if;
  perform show_addons_private.assert_cart(r.cart_id,true);
  delete from public.entry_cart_items where id=r.carrier_id;
  perform show_addons_private.refresh_cart(r.cart_id);
end;
$$;
create function show_addons_private.cart_items(p_cart_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform show_addons_private.assert_cart(p_cart_id);
  return coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at,r.id) from show_addons_private.selections r where r.cart_id=p_cart_id),'[]');
end;
$$;
create function show_addons_private.registrations(p_show_id uuid default null,p_owner_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to view registrations.' using errcode='42501'; end if;
  if p_show_id is not null then
    if not public.user_can_manage_show_settings(p_show_id) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  elsif p_owner_id is null or not household_private.has_access(p_owner_id) then raise exception 'Household access is required.' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('show_name',s.name,'exhibitor_name',coalesce(nullif(e.showing_name,''),e.display_name),
    'exhibitor_number',e.exhibitor_number,'email',e.email,'payment_status',coalesce(b.payment_status,c.payment_status),
    'currency',coalesce(b.currency,c.currency,'usd')) order by s.start_date,r.created_at,r.id)
    from show_addons_private.selections r join public.entry_carts c on c.id=r.cart_id join public.shows s on s.id=r.show_id
    join public.exhibitors e on e.id=r.exhibitor_id left join public.show_exhibitor_balances b on b.entry_cart_id=r.cart_id and b.exhibitor_id=r.exhibitor_id and b.source='cart'
    where c.status='submitted' and case when p_show_id is not null then r.show_id=p_show_id else c.user_id=p_owner_id end),'[]');
end;
$$;

create function show_addons_private.guard_carrier()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if ((tg_op<>'INSERT' and old.is_show_addon_carrier) or (tg_op<>'DELETE' and new.is_show_addon_carrier))
    and current_user not in ('postgres','service_role','supabase_admin') then raise exception 'Use the contests and add-ons cart controls to change this item.' using errcode='42501'; end if;
  if tg_op='DELETE' then return old; end if;
  if new.is_show_addon_carrier and (not new.is_checkin_fee_carrier or coalesce(new.is_fur,false) or new.animal_id is not null) then raise exception 'Invalid contest or add-ons carrier.'; end if;
  return new;
end;
$$;
create trigger guard_show_addon_carrier before insert or update or delete on public.entry_cart_items
for each row execute function show_addons_private.guard_carrier();

create function show_addons_private.apply_balance()
returns trigger language plpgsql security definer set search_path='' as $$
declare amount integer; previous integer:=coalesce((new.fee_snapshot->>'addons_subtotal_cents')::integer,0); lines jsonb;
begin
  if new.source<>'cart' then return new; end if;
  if tg_op='UPDATE' and current_setting('ringmaster.payment_state_write',true) is distinct from 'on'
    and (old.paid_online_cents<>0 or old.paid_manual_cents<>0 or old.refunded_cents<>0 or exists(select 1 from public.entry_carts c where c.id=new.entry_cart_id
      and (c.active_payment_session_id is not null or c.completed_payment_session_id is not null))) then new.addons_subtotal_cents:=old.addons_subtotal_cents; return new; end if;
  select coalesce(sum(quantity::bigint*unit_price_cents),0)::integer,coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'kind',kind,
    'quantity',quantity,'unit_price_cents',unit_price_cents,'amount_cents',quantity::bigint*unit_price_cents) order by created_at,id),'[]')
    into amount,lines from show_addons_private.selections where cart_id=new.entry_cart_id and exhibitor_id=new.exhibitor_id;
  if amount=0 and previous=0 and lines='[]'::jsonb then return new; end if;
  new.addons_subtotal_cents:=amount;
  new.subtotal_before_discount_cents:=new.subtotal_before_discount_cents+amount-previous;
  new.calculated_total_cents:=greatest(new.calculated_total_cents+amount-previous,0);
  new.balance_due_cents:=greatest(new.calculated_total_cents-new.paid_online_cents-new.paid_manual_cents+new.refunded_cents,0);
  new.fee_snapshot:=coalesce(new.fee_snapshot,'{}')||jsonb_build_object('addons_subtotal_cents',amount,'addons',lines,
    'subtotal_before_discount_cents',new.subtotal_before_discount_cents,'calculated_total_cents',new.calculated_total_cents);
  if new.payment_status not in ('pending','refunded','overpaid') then new.payment_status:=case when new.balance_due_cents=0 then 'paid'
    when new.paid_online_cents+new.paid_manual_cents>0 then 'partial' else 'unpaid' end; end if;
  return new;
end;
$$;
create trigger za_apply_show_addons before insert or update on public.show_exhibitor_balances
for each row execute function show_addons_private.apply_balance();

create function show_addons_private.validate_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; r record; o show_addons_private.offerings%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart;
  for r in select * from show_addons_private.selections where cart_id=p_cart order by offering_id loop
    select * into o from show_addons_private.offerings where id=r.offering_id for update;
    perform show_addons_private.assert_eligible(c,o,r.exhibitor_id);
    perform show_addons_private.validate_fields(r.fields,r.answers);
    perform show_addons_private.validate_choices(c,o,r.exhibitor_id,r.division,r.animal_key);
    if r.quantity+(select coalesce(sum(x.quantity),0) from show_addons_private.selections x join public.entry_carts ec on ec.id=x.cart_id
      where x.offering_id=o.id and x.exhibitor_id=r.exhibitor_id and x.cart_id<>p_cart and ec.status in ('active','submitted'))>o.max_per_exhibitor then
      raise exception 'The entry or quantity limit for % has been reached.',o.name;
    end if;
  end loop;
end;
$$;
create function show_addons_private.commit_free(p_cart_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype;
begin
  c:=show_addons_private.assert_cart(p_cart_id,true);
  if not exists(select 1 from show_addons_private.selections where cart_id=c.id)
    or exists(select 1 from public.entry_cart_items where cart_id=c.id and not is_show_addon_carrier) then raise exception 'Use normal checkout for animal entries and other fees.'; end if;
  perform show_addons_private.validate_cart(c.id);
  perform show_addons_private.refresh_cart(c.id);
  if exists(select 1 from public.show_exhibitor_balances where entry_cart_id=c.id and calculated_total_cents<>0) then raise exception 'This cart requires payment.'; end if;
  update public.entry_carts set status='submitted',submitted_at=now(),payment_status='paid',updated_at=now() where id=c.id;
end;
$$;

-- Extend established calculations, preserving all existing discounts/fees.
do $migration$
declare d text; f text;
begin
  d:=pg_get_functiondef('public.calculate_entry_cart_balance_without_canada_special(uuid)'::regprocedure);
  if strpos(d,'coalesce(eci.is_exhibitor_fee_carrier, false) as is_exhibitor_fee_carrier')=0 then raise exception 'Unexpected cart calculator; review before applying.'; end if;
  d:=replace(d,'coalesce(eci.is_exhibitor_fee_carrier, false) as is_exhibitor_fee_carrier',
    '(coalesce(eci.is_exhibitor_fee_carrier, false) or eci.is_show_addon_carrier) as is_exhibitor_fee_carrier');
  execute d;
  d:=pg_get_functiondef('public.calculate_entry_cart_balance_internal(uuid)'::regprocedure);
  if strpos(d,'from public.entry_cart_items eci')=0 then raise exception 'Unexpected Canada-special calculator; review before applying.'; end if;
  d:=replace(d,'from public.entry_cart_items eci','from (select * from public.entry_cart_items where not is_show_addon_carrier) eci');
  execute d;
  -- Day-of and paid materialization must never turn contests/tickets into animals.
  foreach f in array array['public.commit_entry_cart_day_of(uuid)','public.finalize_entry_cart_paid(uuid,uuid,text,text,integer,text)'] loop
    d:=pg_get_functiondef(f::regprocedure);
    if strpos(d,'where i.cart_id = p_cart_id and')=0 then raise exception 'Unexpected checkout materialization.'; end if;
    d:=replace(d,'where i.cart_id = p_cart_id and','where i.cart_id = p_cart_id and not i.is_show_addon_carrier and');
    if f like '%day_of%' then
      if strpos(d,E'  update public.entry_carts\n  set\n    selected_payment_timing')=0 then raise exception 'Unexpected pay-at-show checkout; review before applying.'; end if;
      d:=replace(d,E'  update public.entry_carts\n  set\n    selected_payment_timing',E'  perform show_addons_private.validate_cart(p_cart_id);\n  perform public.calculate_entry_cart_balance_internal(p_cart_id);\n\n  update public.entry_carts\n  set\n    selected_payment_timing');
    end if;
    execute d;
  end loop;
  d:=pg_get_functiondef('public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)'::regprocedure);
  if strpos(d,'  perform public.calculate_entry_cart_balance(p_cart_id);')=0 or strpos(d,'  if v_online_fee <> 0 then')=0 then raise exception 'Unexpected payment quote function.'; end if;
  d:=replace(d,'  perform public.calculate_entry_cart_balance(p_cart_id);',E'  perform show_addons_private.validate_cart(p_cart_id);\n  perform public.calculate_entry_cart_balance(p_cart_id);');
  d:=replace(d,'  if v_online_fee <> 0 then',E'  insert into public.show_payment_line_items(payment_session_id,cart_id,exhibitor_id,balance_id,item_type,line_type,label,quantity,unit_amount_cents,total_amount_cents,metadata)\n  select v_session_id,p_cart_id,r.exhibitor_id,b.id,\'other\',\'adjustment\',r.name,r.quantity,r.unit_price_cents,r.quantity*r.unit_price_cents,\n    jsonb_build_object(\'show_addon_id\',r.id,\'kind\',r.kind,\'quote_hash\',v_quote_hash)\n  from show_addons_private.selections r join public.show_exhibitor_balances b on b.entry_cart_id=r.cart_id and b.exhibitor_id=r.exhibitor_id and b.source=\'cart\' where r.cart_id=p_cart_id;\n\n  if v_online_fee <> 0 then');
  execute d;
end;
$migration$;

-- Private helpers are never exposed; public RPCs delegate to guarded functions.
revoke all on all functions in schema show_addons_private from public,anon,authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'catalog(uuid,boolean)','set_enabled(uuid,text,boolean)','save_offering(uuid,jsonb)',
    'save_selection(uuid,uuid,uuid,integer,jsonb,text,text)','contest_animals(uuid,uuid)','remove_selection(uuid)','cart_items(uuid)',
    'registrations(uuid,uuid)','commit_free(uuid)'] loop
    execute 'grant execute on function show_addons_private.'||f||' to authenticated,service_role';
  end loop;
end;
$$;
create function public.get_show_addons(p_show_id uuid,p_admin boolean default false) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.catalog(p_show_id,p_admin); $$;
create function public.set_show_addons_enabled(p_show_id uuid,p_kind text,p_enabled boolean) returns void language sql security invoker set search_path='' as $$ select show_addons_private.set_enabled(p_show_id,p_kind,p_enabled); $$;
create function public.save_show_addon(p_show_id uuid,p_item jsonb) returns uuid language sql security invoker set search_path='' as $$ select show_addons_private.save_offering(p_show_id,p_item); $$;
create function public.save_cart_addon(p_cart_id uuid,p_offering_id uuid,p_exhibitor_id uuid,p_quantity integer,p_answers jsonb,p_division text default null,p_animal_key text default null) returns uuid language sql security invoker set search_path='' as $$ select show_addons_private.save_selection(p_cart_id,p_offering_id,p_exhibitor_id,p_quantity,p_answers,p_division,p_animal_key); $$;
create function public.get_contest_animals(p_cart_id uuid,p_exhibitor_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.contest_animals(p_cart_id,p_exhibitor_id); $$;
create function public.remove_cart_addon(p_selection_id uuid) returns void language sql security invoker set search_path='' as $$ select show_addons_private.remove_selection(p_selection_id); $$;
create function public.get_cart_addons(p_cart_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.cart_items(p_cart_id); $$;
create function public.get_show_addon_registrations(p_show_id uuid default null,p_owner_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.registrations(p_show_id,p_owner_id); $$;
create function public.commit_free_addon_cart(p_cart_id uuid) returns void language sql security invoker set search_path='' as $$ select show_addons_private.commit_free(p_cart_id); $$;
do $$
declare f text;
begin
  foreach f in array array['get_show_addons(uuid,boolean)','set_show_addons_enabled(uuid,text,boolean)','save_show_addon(uuid,jsonb)',
    'save_cart_addon(uuid,uuid,uuid,integer,jsonb,text,text)','get_contest_animals(uuid,uuid)','remove_cart_addon(uuid)','get_cart_addons(uuid)',
    'get_show_addon_registrations(uuid,uuid)','commit_free_addon_cart(uuid)'] loop
    execute 'revoke all on function public.'||f||' from public,anon';
    execute 'grant execute on function public.'||f||' to authenticated,service_role';
  end loop;
end;
$$;
