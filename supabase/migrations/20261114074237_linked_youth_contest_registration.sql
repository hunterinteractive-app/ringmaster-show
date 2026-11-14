-- Share selected youth contests without copying offerings, fees, limits or results.
create table show_addons_private.contest_show_links (
  offering_id uuid not null references show_addons_private.offerings(id) on delete cascade,
  source_show_id uuid not null references public.shows(id) on delete cascade,
  primary key(offering_id,source_show_id)
);
create index on show_addons_private.contest_show_links(source_show_id);
alter table show_addons_private.contest_show_links enable row level security;
revoke all on show_addons_private.contest_show_links from public,anon,authenticated;

-- Only the two existing Houston rabbit/cavy contests accept the Cavy show.
insert into show_addons_private.contest_show_links(offering_id,source_show_id)
select o.id,s.id from show_addons_private.offerings o
join public.shows host on host.id=o.show_id
join public.shows s on s.club_id=host.club_id and s.owner_user_id=host.owner_user_id
where o.id in ('d7d7a597-8964-4ef3-aad6-556ccd8de6b6','b2cc40be-d085-46ab-b3e0-78a2eb0937ce')
  and host.id='275bbfe9-6ef7-4c86-b914-23afee7ceffc'
  and s.id='62c1a1ea-da4d-4ac5-a23e-065d14dce251'
  and host.owner_user_id='bca983ed-59ac-4615-a9a7-a2ce56d3d8e8'
  and host.club_id='48522136-118e-4860-aa46-1abb2d783809';

create function show_addons_private.offering_accepts_show(p_offering uuid,p_show uuid)
returns boolean language sql stable set search_path='' as $$
  select exists(select 1 from show_addons_private.offerings o where o.id=p_offering
    and (o.show_id=p_show or (o.kind='contest' and exists(
      select 1 from show_addons_private.contest_show_links l where l.offering_id=o.id and l.source_show_id=p_show))));
$$;

create function show_addons_private.offering_animals(p_cart public.entry_carts,p_ex uuid,p_offering uuid)
returns jsonb language plpgsql stable set search_path='' as $$
declare result jsonb;
begin
  if not show_addons_private.offering_accepts_show(p_offering,p_cart.show_id) then return '[]'; end if;
  if not exists(select 1 from public.exhibitors where id=p_ex and owner_user_id=p_cart.user_id and is_active) then return '[]'; end if;
  if not exists(select 1 from show_addons_private.contest_show_links where offering_id=p_offering) then
    return show_addons_private.animal_choices(p_cart,p_ex);
  end if;
  -- Shared youth contests use youth entries only. An animal can come from a
  -- completed linked show, or this cart; another unpaid cart is not eligibility.
  with eligible as (
    select e.id,e.animal_id,e.species::text species,e.breed,e.tattoo,e.animal_name,
      e.show_id, 'entry'::text source,0 priority
    from public.entries e join public.show_sections s on s.id=e.section_id and s.show_id=e.show_id
    where e.exhibitor_id=p_ex and lower(s.kind::text)='youth' and not coalesce(e.is_fur,false)
      and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled','canceled','withdrawn')
      and show_addons_private.offering_accepts_show(p_offering,e.show_id)
    union all
    select i.id,i.animal_id,i.species::text,i.breed,i.tattoo,i.animal_name,
      p_cart.show_id,'cart',1
    from public.entry_cart_items i join public.show_sections s on s.id=i.section_id and s.show_id=p_cart.show_id
    where i.cart_id=p_cart.id and i.exhibitor_id=p_ex and lower(s.kind::text)='youth'
      and not i.is_checkin_fee_carrier and not coalesce(i.is_fur,false)
  ), keyed as (
    select *,case when animal_id is not null then 'animal:'||animal_id::text
      when nullif(btrim(tattoo),'') is not null then 'tag:'||md5(jsonb_build_array(lower(species),lower(btrim(breed)),btrim(tattoo))::text)
      else source||':'||id::text end animal_key from eligible
  ), animals as (select distinct on(animal_key) * from keyed order by animal_key,priority,id)
  select coalesce(jsonb_agg(jsonb_build_object('key',animal_key,'source',source,'source_id',id,
    'source_show_id',show_id,'animal_id',animal_id,'species',species,'breed',breed,'tattoo',tattoo,'animal_name',animal_name,
    'label',concat_ws(' • ',nullif(animal_name,''),initcap(species),nullif(breed,''),'Ear #: '||coalesce(nullif(tattoo,''),'—')))
    order by lower(breed),tattoo,animal_key),'[]') into result from animals;
  return result;
end; $$;

create function public.get_offering_contest_animals(p_cart_id uuid,p_exhibitor_id uuid,p_offering_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype;
begin
  c:=show_addons_private.assert_cart(p_cart_id);
  if not exists(select 1 from public.exhibitors where id=p_exhibitor_id and owner_user_id=c.user_id and is_active) then
    raise exception 'Choose an active exhibitor from this household.' using errcode='42501';
  end if;
  return show_addons_private.offering_animals(c,p_exhibitor_id,p_offering_id);
end; $$;

CREATE OR REPLACE FUNCTION show_addons_private.assert_eligible(p_cart entry_carts, p_offer show_addons_private.offerings, p_ex uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.shows%rowtype; opens timestamptz; closes timestamptz;
begin
  select * into s from public.shows where id=p_offer.show_id;
  if not show_addons_private.offering_accepts_show(p_offer.id,p_cart.show_id) or p_offer.deleted_at is not null or not p_offer.enabled or not (case when p_offer.kind='contest' then s.contests_enabled else s.extras_enabled end)
    or not coalesce(s.is_published,false) then raise exception 'This contest or add-on is not available.'; end if;
  if exists(select 1 from public.shows src where src.id=p_cart.show_id and (not coalesce(src.is_published,false) or coalesce(src.is_locked,false) or src.finalized_at is not null)) then raise exception 'The entry show is unavailable or locked.'; end if;
  if coalesce(s.is_locked,false) or s.finalized_at is not null then raise exception 'This show is locked or finalized.'; end if;
  opens:=case when p_offer.use_show_entry_dates then s.entry_open_at else p_offer.registration_open_at end;
  closes:=case when p_offer.use_show_entry_dates then s.entry_close_at else p_offer.registration_close_at end;
  if opens>now() or closes<now() then raise exception 'Registration is outside the registration window for %.',p_offer.name; end if;
  if not exists(select 1 from public.exhibitors e where e.id=p_ex and e.owner_user_id=p_cart.user_id and e.is_active) then
    raise exception 'Choose an active exhibitor from this household.' using errcode='42501'; end if;
  if exists(select 1 from show_addons_private.contest_show_links where offering_id=p_offer.id) then
    if jsonb_array_length(show_addons_private.offering_animals(p_cart,p_ex,p_offer.id))=0 then
      raise exception '% requires a youth animal entry in the rabbit or linked cavy show for this exhibitor.',p_offer.name;
    end if;
    return;
  end if;
  if p_offer.requires_animal_entry and not (
    exists(select 1 from public.entries e where e.show_id=s.id and e.exhibitor_id=p_ex and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled','withdrawn'))
    or exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart.id and i.exhibitor_id=p_ex and not i.is_checkin_fee_carrier and not coalesce(i.is_fur,false))) then
    raise exception '% requires an animal entry for this exhibitor in this show.',p_offer.name;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION show_addons_private.validate_choices(p_cart entry_carts, p_offer show_addons_private.offerings, p_ex uuid, p_division text, p_animal_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare snapshot jsonb;
begin
  if jsonb_array_length(p_offer.divisions)>0 then
    if p_division is null or not (p_offer.divisions ? p_division) then raise exception 'Choose a valid division for %.',p_offer.name; end if;
  elsif p_division is not null then raise exception 'This contest does not use divisions.'; end if;
  if p_offer.animal_selection='required' and p_animal_key is null then raise exception 'Choose an entered animal for %.',p_offer.name; end if;
  if p_animal_key is not null then
    if p_offer.animal_selection='none' then raise exception 'This contest does not use animal selection.'; end if;
    select value into snapshot from jsonb_array_elements(show_addons_private.offering_animals(p_cart,p_ex,p_offer.id)) where value->>'key'=p_animal_key;
    if snapshot is null then raise exception 'Choose an eligible animal entered for this exhibitor in this show.'; end if;
  end if;
  return snapshot;
end;
$function$;

CREATE OR REPLACE FUNCTION show_addons_private.registration_data(p_cart entry_carts, p_offer show_addons_private.offerings, p_ex uuid, p_data jsonb, p_division text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg jsonb:=p_offer.contest_config; d jsonb:=coalesce(p_data,'{}'); r jsonb; member jsonb; ages integer[]:='{}';
  n integer; active_count integer:=0; alternates integer:=0; cutoff date; birthday date; chosen_age integer;
  animals jsonb:='[]'; a jsonb; snapshot jsonb; keys text[]:='{}'; rules jsonb;
begin
  if jsonb_typeof(d)<>'object' or length(d::text)>60000 then raise exception 'Invalid registration details.'; end if;
  if p_offer.kind<>'contest' then
    if d<>'{}'::jsonb then raise exception 'Registration details are only used for contests.'; end if;
    return d;
  end if;
  if jsonb_array_length(coalesce(cfg->'categories','[]'))>0 then
    if not(cfg->'categories' ? coalesce(d->>'category','')) then raise exception 'Choose a contest category.'; end if;
  elsif nullif(d->>'category','') is not null then raise exception 'This contest does not use categories.'; end if;
  if jsonb_array_length(coalesce(cfg->'sessions','[]'))>0 then
    select value into r from jsonb_array_elements(cfg->'sessions') where value->>'id'=d->>'session_id';
    if r is null then raise exception 'Choose a contest session.'; end if;
    d:=d||jsonb_build_object('session_name',r->>'name');
  elsif nullif(d->>'session_id','') is not null then raise exception 'This contest does not use sessions.'; end if;
  if cfg->>'entry_type'='project' and length(btrim(coalesce(d->>'project_title',''))) not between 1 and 200 then raise exception 'Enter a project title.'; end if;
  select case coalesce(cfg->>'age_as_of','show_start') when 'custom' then (cfg->>'age_date')::date
    when 'show_end' then s.end_date else s.start_date end into cutoff from public.shows s where s.id=p_offer.show_id;
  if cfg->>'entry_type'='team' then
    if length(btrim(coalesce(d#>>'{team,name}',''))) not between 1 and 120
      or jsonb_typeof(d#>'{team,members}') is distinct from 'array' or jsonb_array_length(d#>'{team,members}')>30
      or d#>'{team,authorized}' is distinct from 'true'::jsonb then raise exception 'Enter the team name, roster, and coordinator authorization.'; end if;
    for member in select value from jsonb_array_elements(d#>'{team,members}') loop
      if length(btrim(coalesce(member->>'name',''))) not between 1 and 120 or coalesce(member->>'birthdate','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        or to_char((member->>'birthdate')::date,'YYYY-MM-DD')<>member->>'birthdate' then raise exception 'Each team member needs a name and valid birthdate.'; end if;
      birthday:=(member->>'birthdate')::date;
      if birthday>current_date or birthday<current_date-interval '120 years' then raise exception 'Check the team member birthdate.'; end if;
      if lower(btrim(member->>'name'))||'|'||birthday::text=any(keys) then raise exception 'A member can appear only once on a team.'; end if;
      keys:=array_append(keys,lower(btrim(member->>'name'))||'|'||birthday::text);
      ages:=array_append(ages,extract(year from age(cutoff,birthday))::integer);
      if coalesce((member->>'alternate')::boolean,false) then alternates:=alternates+1; else active_count:=active_count+1; end if;
      if nullif(cfg->>'prerequisite_contest_id','') is not null and not coalesce((member->>'alternate')::boolean,false) and not exists(
        select 1 from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id join public.exhibitors e on e.id=x.exhibitor_id
        where x.offering_id=(cfg->>'prerequisite_contest_id')::uuid and x.show_id=p_offer.show_id
          and e.exhibitor_number::text=member->>'exhibitor_number' and (c.status='submitted' or c.id=p_cart.id)) then
        raise exception 'Each team member must have an exhibitor number and the required individual contest registration.';
      end if;
    end loop;
    if active_count<coalesce((cfg->>'team_min')::integer,3) or active_count>coalesce((cfg->>'team_max')::integer,4)
      or alternates>coalesce((cfg->>'team_alternates')::integer,0) then raise exception 'The roster does not meet the contest team size.'; end if;
  elsif coalesce((cfg->>'collect_birthdate')::boolean,false) or jsonb_array_length(coalesce(cfg->'age_rules','[]'))>0 then
    if coalesce(d->>'birthdate','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char((d->>'birthdate')::date,'YYYY-MM-DD')<>d->>'birthdate'
      or (d->>'birthdate')::date>current_date or (d->>'birthdate')::date<current_date-interval '120 years' then raise exception 'Enter a valid contestant birthdate.'; end if;
    ages:=array[extract(year from age(cutoff,(d->>'birthdate')::date))::integer];
  end if;
  select value into rules from jsonb_array_elements(coalesce(cfg->'age_rules','[]')) where value->>'division'=p_division;
  if rules is not null then
    if cfg->>'entry_type'='team' and coalesce(cfg->>'team_age_rule','oldest')='oldest' then
      select max(v) into chosen_age from unnest(ages) v; ages:=array[chosen_age];
    end if;
    foreach n in array ages loop
      if n<(rules->>'min')::integer or n>(rules->>'max')::integer then raise exception 'The selected division does not match the age requirements.'; end if;
    end loop;
    d:=d||jsonb_build_object('age_cutoff',cutoff);
  end if;
  if jsonb_array_length(coalesce(cfg->'animal_sources','[]'))>0 or jsonb_array_length(coalesce(cfg->'animal_roles','[]'))>0 then
    if jsonb_typeof(coalesce(d->'animals','[]'))<>'array' or jsonb_array_length(coalesce(d->'animals','[]'))>10 then raise exception 'Invalid animal choices.'; end if;
    if p_offer.animal_selection='required' and jsonb_array_length(coalesce(d->'animals','[]'))<>greatest(jsonb_array_length(coalesce(cfg->'animal_roles','[]')),1) then raise exception 'Complete each animal choice.'; end if;
    keys:='{}';
    for a in select value from jsonb_array_elements(coalesce(d->'animals','[]')) loop
      if not(coalesce(nullif(cfg->'animal_sources','[]'::jsonb),'["entered"]') ? coalesce(a->>'source','')) then raise exception 'Choose an allowed animal source.'; end if;
      if jsonb_array_length(coalesce(cfg->'animal_roles','[]'))>0 and not(cfg->'animal_roles' ? coalesce(a->>'role','')) then raise exception 'Choose an animal for each role.'; end if;
      if coalesce(a->>'role','Animal')=any(keys) then raise exception 'Choose one animal per role.'; end if;
      keys:=array_append(keys,coalesce(a->>'role','Animal'));
      if a->>'source'='entered' then
        select value into snapshot from jsonb_array_elements(show_addons_private.offering_animals(p_cart,p_ex,p_offer.id)) where value->>'key'=a->>'key';
        if snapshot is null then raise exception 'Choose an eligible entered animal.'; end if;
        a:=snapshot||jsonb_build_object('source','entered','role',a->>'role');
      elsif a->>'source'='own' then
        if coalesce(a->>'species','') not in ('rabbit','cavy') or length(btrim(coalesce(a->>'label',''))) not between 1 and 250 then raise exception 'Describe the animal you will bring.'; end if;
      else a:=jsonb_build_object('source','provided','role',a->>'role','label','Organizer-provided animal'); end if;
      animals:=animals||jsonb_build_array(a);
    end loop;
    d:=d||jsonb_build_object('animals',animals);
  end if;
  return d;
end; $function$;

CREATE OR REPLACE FUNCTION show_addons_private.save_registration(p_cart_id uuid, p_offering_id uuid, p_exhibitor_id uuid, p_quantity integer, p_answers jsonb, p_division text, p_animal_key text, p_data jsonb, p_id uuid, p_staff boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.entry_carts%rowtype; o show_addons_private.offerings%rowtype; choices show_addons_private.offerings%rowtype;
  r show_addons_private.selections%rowtype; carrier uuid; section uuid; animal jsonb; fields jsonb; data jsonb; v_registration_id uuid:=coalesce(p_id,extensions.gen_random_uuid());
begin
  if p_staff then
    select * into c from public.entry_carts where id=p_cart_id for update;
    perform show_addons_private.assert_secretary(c.show_id);
    if c.status<>'active' or c.active_payment_session_id is not null then raise exception 'This cart is no longer editable.'; end if;
  else c:=show_addons_private.assert_cart(p_cart_id,true); end if;
  select * into o from show_addons_private.offerings where id=p_offering_id for update;
  if not found then raise exception 'Item not found.'; end if;
  if o.results_published_at is not null then raise exception 'Registration is closed because results have been published.'; end if;
  if p_staff then
    if o.kind<>'contest' or not coalesce((o.contest_config->>'allow_walkup')::boolean,false) then raise exception 'Enable walk-up registrations in this contest’s settings first.'; end if;
    if o.show_id<>c.show_id or not exists(select 1 from public.exhibitors e where e.id=p_exhibitor_id and e.owner_user_id=c.user_id and e.is_active) then raise exception 'Invalid exhibitor or contest.'; end if;
    choices:=o; choices.use_show_entry_dates:=false; choices.registration_open_at:=null; choices.registration_close_at:=null;
    perform show_addons_private.assert_eligible(c,choices,p_exhibitor_id);
  else perform show_addons_private.assert_eligible(c,o,p_exhibitor_id); end if;
  select * into r from show_addons_private.selections where selections.id=v_registration_id;
  if found and (r.cart_id<>c.id or r.offering_id<>o.id or r.exhibitor_id<>p_exhibitor_id) then raise exception 'This registration belongs to a different cart or exhibitor.' using errcode='42501'; end if;
  p_division:=nullif(btrim(p_division),''); p_animal_key:=nullif(btrim(p_animal_key),'');
  choices:=o;
  if jsonb_array_length(coalesce(o.contest_config->'animal_sources','[]'))>0 or jsonb_array_length(coalesce(o.contest_config->'animal_roles','[]'))>0 then
    choices.animal_selection:='none'; p_animal_key:=null;
  end if;
  animal:=show_addons_private.validate_choices(c,choices,p_exhibitor_id,p_division,p_animal_key);
  data:=show_addons_private.registration_data(c,o,p_exhibitor_id,p_data,p_division);
  perform show_addons_private.validate_registration_limits(c,o,p_exhibitor_id,p_quantity,data,v_registration_id);
  fields:=show_addons_private.effective_fields(o.fields,data,p_division);
  perform show_addons_private.validate_fields(fields,p_answers);
  perform show_addons_private.validate_uploads(o.id,c.user_id,fields,p_answers);
  if not p_staff and nullif(o.contest_config->>'submission_close_at','') is not null and (o.contest_config->>'submission_close_at')::timestamptz<now() then raise exception 'The submission deadline has passed.'; end if;
  if r.id is not null then carrier:=r.carrier_id;
  else
    select sections.id into section from public.show_sections sections where show_id=c.show_id order by sort_order,sections.id limit 1;
    if section is null then raise exception 'The secretary must set up at least one show section before accepting registrations.'; end if;
    insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,is_checkin_fee_carrier,is_show_addon_carrier)
      values(c.id,section,p_exhibitor_id,'rabbit','SHOW-ADDON',true,true) returning entry_cart_items.id into carrier;
  end if;
  insert into show_addons_private.selections(id,offering_id,show_id,cart_id,exhibitor_id,carrier_id,quantity,unit_price_cents,name,kind,fields,answers,division,animal_key,animal_snapshot,registration_data,config_snapshot)
    values(v_registration_id,o.id,o.show_id,c.id,p_exhibitor_id,carrier,p_quantity,o.price_cents,o.name,o.kind,fields,p_answers,p_division,p_animal_key,animal,data,o.contest_config)
    on conflict on constraint selections_pkey do update set quantity=excluded.quantity,unit_price_cents=excluded.unit_price_cents,
      name=excluded.name,fields=excluded.fields,answers=excluded.answers,division=excluded.division,animal_key=excluded.animal_key,
      animal_snapshot=excluded.animal_snapshot,registration_data=excluded.registration_data,config_snapshot=excluded.config_snapshot,updated_at=now();
  delete from show_addons_private.contest_drafts where contest_drafts.id=v_registration_id and cart_id=c.id;
  perform show_addons_private.refresh_cart(c.id);
  return v_registration_id;
end; $function$;

CREATE OR REPLACE FUNCTION show_addons_private.catalog(p_show_id uuid, p_admin boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.shows%rowtype; items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in to view contests and add-ons.' using errcode='42501'; end if;
  select * into s from public.shows where id=p_show_id;
  if not found or (not coalesce(s.is_published,false) and not public.user_can_manage_show_settings(p_show_id)) then raise exception 'Show is unavailable.' using errcode='42501'; end if;
  if p_admin and not public.user_can_manage_show_settings(p_show_id) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object(
      'host_show_name',case when o.show_id<>p_show_id then host.name end,
      'effective_open_at',case when o.use_show_entry_dates then host.entry_open_at else o.registration_open_at end,
      'effective_close_at',case when o.use_show_entry_dates then host.entry_close_at else o.registration_close_at end,
      'effective_age_date',case coalesce(o.contest_config->>'age_as_of','show_start') when 'custom' then (o.contest_config->>'age_date')::date when 'show_end' then host.end_date else host.start_date end,
      'registration_status',case when o.results_published_at is not null then 'closed' when coalesce(s.is_locked,false) or s.finalized_at is not null or coalesce(host.is_locked,false) or host.finalized_at is not null then 'locked'
        when (case when o.use_show_entry_dates then host.entry_open_at else o.registration_open_at end)>now() then 'upcoming'
        when (case when o.use_show_entry_dates then host.entry_close_at else o.registration_close_at end)<now() then 'closed'
        else 'open' end) order by lower(o.name),o.id),'[]') into items from show_addons_private.offerings o join public.shows host on host.id=o.show_id
    where o.deleted_at is null and (
      (p_admin and o.show_id=p_show_id) or
      (not p_admin and o.enabled and coalesce(host.is_published,false)
        and show_addons_private.offering_accepts_show(o.id,p_show_id)
        and case when o.kind='contest' then host.contests_enabled else host.extras_enabled end));
  return jsonb_build_object('contests_enabled',s.contests_enabled or exists(select 1 from jsonb_array_elements(items) i where i->>'kind'='contest'),'extras_enabled',s.extras_enabled,'items',items,
    'currency',coalesce((select lower(currency) from public.show_fee_settings where show_id=p_show_id),'usd'),
    'entry_open_at',s.entry_open_at,'entry_close_at',s.entry_close_at,'locked',coalesce(s.is_locked,false) or s.finalized_at is not null);
end;
$function$;

revoke all on function show_addons_private.offering_accepts_show(uuid,uuid),show_addons_private.offering_animals(public.entry_carts,uuid,uuid) from public,anon,authenticated;
revoke all on function public.get_offering_contest_animals(uuid,uuid,uuid) from public,anon;
grant execute on function public.get_offering_contest_animals(uuid,uuid,uuid) to authenticated;
notify pgrst,'reload schema';
