-- Contests inherit the show's live entry dates unless explicitly overridden.
alter table show_addons_private.offerings
  add column use_show_entry_dates boolean not null default true,
  add column registration_open_at timestamptz,
  add column registration_close_at timestamptz,
  add constraint contest_registration_window check (
    (use_show_entry_dates and registration_open_at is null and registration_close_at is null)
    or (not use_show_entry_dates and kind='contest'
      and registration_open_at is not null and registration_close_at is not null
      and isfinite(registration_open_at) and isfinite(registration_close_at)
      and registration_close_at>registration_open_at)
  );

create or replace function show_addons_private.save_offering(p_show_id uuid,p_item jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_item->>'id')::uuid; existing show_addons_private.offerings%rowtype;
begin
  if p_item->>'kind'<>'contest' and not coalesce((p_item->>'use_show_entry_dates')::boolean,true) then
    raise exception 'Custom registration dates are only available for contests.';
  end if;
  perform show_addons_private.assert_secretary(p_show_id);
  perform show_addons_private.validate_fields(coalesce(p_item->'fields','[]'));
  perform show_addons_private.validate_contest_options(p_item->>'kind',coalesce(p_item->'divisions','[]'),coalesce(p_item->>'animal_selection','none'));
  if not coalesce((p_item->>'use_show_entry_dates')::boolean,true) and (
    nullif(p_item->>'registration_open_at','') is null or nullif(p_item->>'registration_close_at','') is null
    or not isfinite((p_item->>'registration_open_at')::timestamptz)
    or not isfinite((p_item->>'registration_close_at')::timestamptz)
    or (p_item->>'registration_close_at')::timestamptz <= (p_item->>'registration_open_at')::timestamptz) then
    raise exception 'Choose an opening and closing date, with closing after opening.';
  end if;
  select * into existing from show_addons_private.offerings where id=v_id for update;
  if found and (existing.show_id<>p_show_id or existing.kind<>p_item->>'kind') then raise exception 'This item belongs to a different show or type.' using errcode='42501'; end if;
  if p_item->>'kind'='extra' and jsonb_array_length(coalesce(p_item->'fields','[]'))>0 then raise exception 'Add-on items do not use contest fields.'; end if;
  insert into show_addons_private.offerings(id,show_id,kind,name,description,price_cents,enabled,requires_animal_entry,max_per_exhibitor,fields,divisions,animal_selection,use_show_entry_dates,registration_open_at,registration_close_at)
    values(v_id,p_show_id,p_item->>'kind',btrim(p_item->>'name'),coalesce(p_item->>'description',''),(p_item->>'price_cents')::integer,
      coalesce((p_item->>'enabled')::boolean,true),coalesce((p_item->>'requires_animal_entry')::boolean,false),
      case when p_item->>'kind'='contest' then 1 else coalesce((p_item->>'max_per_exhibitor')::integer,99) end,coalesce(p_item->'fields','[]'),
      coalesce((select jsonb_agg(btrim(value#>>'{}')) from jsonb_array_elements(coalesce(p_item->'divisions','[]'))),'[]'),coalesce(p_item->>'animal_selection','none'),
      coalesce((p_item->>'use_show_entry_dates')::boolean,true),
      case when not coalesce((p_item->>'use_show_entry_dates')::boolean,true) then (p_item->>'registration_open_at')::timestamptz end,
      case when not coalesce((p_item->>'use_show_entry_dates')::boolean,true) then (p_item->>'registration_close_at')::timestamptz end)
  on conflict(id) do update set name=excluded.name,description=excluded.description,price_cents=excluded.price_cents,
    enabled=excluded.enabled,requires_animal_entry=excluded.requires_animal_entry,max_per_exhibitor=excluded.max_per_exhibitor,
    fields=excluded.fields,divisions=excluded.divisions,animal_selection=excluded.animal_selection,use_show_entry_dates=excluded.use_show_entry_dates,
    registration_open_at=excluded.registration_open_at,registration_close_at=excluded.registration_close_at,updated_at=now()
    where offerings.show_id=p_show_id and offerings.kind=excluded.kind;
  if not found then raise exception 'This item belongs to a different show or type.' using errcode='42501'; end if;
  return v_id;
end;
$$;

create or replace function show_addons_private.assert_eligible(p_cart public.entry_carts,p_offer show_addons_private.offerings,p_ex uuid)
returns void language plpgsql security definer set search_path='' as $$
declare s public.shows%rowtype; opens timestamptz; closes timestamptz;
begin
  select * into s from public.shows where id=p_cart.show_id;
  if p_offer.show_id<>s.id or not p_offer.enabled or not (case when p_offer.kind='contest' then s.contests_enabled else s.extras_enabled end)
    or not coalesce(s.is_published,false) then raise exception 'This contest or add-on is not available.'; end if;
  if coalesce(s.is_locked,false) or s.finalized_at is not null then raise exception 'This show is locked or finalized.'; end if;
  opens:=case when p_offer.use_show_entry_dates then s.entry_open_at else p_offer.registration_open_at end;
  closes:=case when p_offer.use_show_entry_dates then s.entry_close_at else p_offer.registration_close_at end;
  if opens>now() or closes<now() then raise exception 'Registration is outside the registration window for %.',p_offer.name; end if;
  if not exists(select 1 from public.exhibitors e where e.id=p_ex and e.owner_user_id=p_cart.user_id and e.is_active) then
    raise exception 'Choose an active exhibitor from this household.' using errcode='42501'; end if;
  if p_offer.requires_animal_entry and not (
    exists(select 1 from public.entries e where e.show_id=s.id and e.exhibitor_id=p_ex and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled','withdrawn'))
    or exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart.id and i.exhibitor_id=p_ex and not i.is_checkin_fee_carrier and not coalesce(i.is_fur,false))) then
    raise exception '% requires an animal entry for this exhibitor in this show.',p_offer.name;
  end if;
end;
$$;

create or replace function show_addons_private.catalog(p_show_id uuid,p_admin boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.shows%rowtype; items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in to view contests and add-ons.' using errcode='42501'; end if;
  select * into s from public.shows where id=p_show_id;
  if not found or (not coalesce(s.is_published,false) and not public.user_can_manage_show_settings(p_show_id)) then raise exception 'Show is unavailable.' using errcode='42501'; end if;
  if p_admin and not public.user_can_manage_show_settings(p_show_id) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object(
      'effective_open_at',case when o.use_show_entry_dates then s.entry_open_at else o.registration_open_at end,
      'effective_close_at',case when o.use_show_entry_dates then s.entry_close_at else o.registration_close_at end,
      'registration_status',case when coalesce(s.is_locked,false) or s.finalized_at is not null then 'locked'
        when (case when o.use_show_entry_dates then s.entry_open_at else o.registration_open_at end)>now() then 'upcoming'
        when (case when o.use_show_entry_dates then s.entry_close_at else o.registration_close_at end)<now() then 'closed'
        else 'open' end) order by lower(o.name),o.id),'[]') into items from show_addons_private.offerings o
    where o.show_id=p_show_id and (p_admin or (o.enabled and case when o.kind='contest' then s.contests_enabled else s.extras_enabled end));
  return jsonb_build_object('contests_enabled',s.contests_enabled,'extras_enabled',s.extras_enabled,'items',items,
    'currency',coalesce((select lower(currency) from public.show_fee_settings where show_id=p_show_id),'usd'),
    'entry_open_at',s.entry_open_at,'entry_close_at',s.entry_close_at,'locked',coalesce(s.is_locked,false) or s.finalized_at is not null);
end;
$$;

-- Keep shows discoverable while a custom contest is open after animal entries close.
create function show_addons_private.open_contest_shows()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to view contests.' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',s.id,'name',s.name,'start_date',s.start_date,'location_name',s.location_name,
    'entry_close_at',s.entry_close_at,'is_demo',s.is_demo,'demo_resets_at',s.demo_resets_at,
    'contest_registration_open',true) order by s.start_date,s.id)
    from public.shows s where s.is_published and s.contests_enabled
      and not coalesce(s.is_locked,false) and s.finalized_at is null
      and exists(select 1 from show_addons_private.offerings o where o.show_id=s.id
        and o.kind='contest' and o.enabled and not o.use_show_entry_dates
        and now() between o.registration_open_at and o.registration_close_at)), '[]');
end;
$$;
revoke all on function show_addons_private.open_contest_shows() from public,anon,authenticated;
grant execute on function show_addons_private.open_contest_shows() to authenticated,service_role;
create function public.get_open_contest_shows()
returns jsonb language sql security invoker set search_path='' as $$select show_addons_private.open_contest_shows();$$;
revoke all on function public.get_open_contest_shows() from public,anon;
grant execute on function public.get_open_contest_shows() to authenticated,service_role;

-- The shared quote/day-of paths still enforce animal deadlines. Add-on-only carts
-- use each offering's authoritative window via validate_cart before submission.
do $migration$
declare signature text; definition text; old_guard text := 'if v_show.entry_close_at is not null and v_now > v_show.entry_close_at then';
begin
  foreach signature in array array[
    'public.commit_entry_cart_day_of(uuid)',
    'public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)'
  ] loop
    definition:=pg_get_functiondef(signature::regprocedure);
    if strpos(definition,old_guard)=0 or strpos(definition,'show_addons_private.validate_cart(p_cart_id)')=0 then
      raise exception 'Unexpected checkout function: %',signature;
    end if;
    definition:=replace(definition,old_guard,
      'if v_show.entry_close_at is not null and v_now > v_show.entry_close_at and exists (select 1 from public.entry_cart_items where cart_id=p_cart_id and not is_show_addon_carrier) then');
    execute definition;
  end loop;
end;
$migration$;

create or replace function show_addons_private.validate_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; r record; o show_addons_private.offerings%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart;
  if exists(select 1 from show_addons_private.selections where cart_id=p_cart)
    and exists(select 1 from public.entry_cart_items where cart_id=p_cart and not is_show_addon_carrier)
    and exists(select 1 from public.shows where id=c.show_id and (entry_open_at>now() or entry_close_at<now())) then
    raise exception 'Remove animal entries from the cart to register for contests outside the show entry window.';
  end if;
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
