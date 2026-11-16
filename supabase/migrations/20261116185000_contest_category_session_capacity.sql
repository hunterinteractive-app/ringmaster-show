-- Optional shared capacity for each contest category in each session.
-- Defaults to unlimited; existing per-exhibitor and session limits stay separate.
create or replace function show_addons_private.validate_config(p jsonb,p_divisions jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare r jsonb; k text; ids text[]:='{}';
begin
  if jsonb_typeof(p) is distinct from 'object' or length(p::text)>60000 then raise exception 'Invalid contest settings.'; end if;
  if coalesce(p->>'entry_type','individual') not in ('individual','team','project') then raise exception 'Choose individual, team, or project entry.'; end if;
  foreach k in array array['collect_birthdate','requires_approval','results_enabled','allow_ties','allow_walkup'] loop
    if p ? k and jsonb_typeof(p->k) is distinct from 'boolean' then raise exception 'Invalid setting for %.',k; end if;
  end loop;
  if length(coalesce(p->>'schedule_notes',''))>10000 then raise exception 'Schedule notes are too long.'; end if;
  perform show_addons_private.string_list(coalesce(p->'categories','[]'),'Categories');
  perform show_addons_private.string_list(coalesce(p->'animal_roles','[]'),'Animal roles',10);
  perform show_addons_private.string_list(coalesce(p->'animal_sources','[]'),'Animal sources',3);
  if exists(select 1 from jsonb_array_elements_text(coalesce(p->'animal_sources','[]')) v where v not in ('entered','own','provided')) then raise exception 'Invalid animal source.'; end if;
  foreach k in array array['capacity','category_limit','category_session_capacity','max_awarded_per_exhibitor','places','team_min','team_max','team_alternates'] loop
    if p ? k and (jsonb_typeof(p->k)<>'number' or (p->>k)!~'^[0-9]+$' or (p->>k)::integer>100000) then raise exception 'Invalid number for %.',k; end if;
  end loop;
  if coalesce(p->>'entry_type','individual')='team' and (coalesce((p->>'team_min')::integer,3)<1
    or coalesce((p->>'team_max')::integer,4)<coalesce((p->>'team_min')::integer,3)
    or coalesce((p->>'team_max')::integer,4)>20 or coalesce((p->>'team_alternates')::integer,0)>10) then raise exception 'Invalid team size.'; end if;
  if coalesce(p->>'team_age_rule','oldest') not in ('oldest','all') then raise exception 'Invalid team age rule.'; end if;
  if coalesce(p->>'age_as_of','show_start') not in ('show_start','show_end','custom') then raise exception 'Invalid age cutoff setting.'; end if;
  if p->>'age_as_of'='custom' and (coalesce(p->>'age_date','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or to_char((p->>'age_date')::date,'YYYY-MM-DD')<>p->>'age_date') then raise exception 'Set a valid age cutoff date.'; end if;
  if jsonb_typeof(coalesce(p->'age_rules','[]'))<>'array' or jsonb_array_length(coalesce(p->'age_rules','[]'))>100 then raise exception 'Invalid age rules.'; end if;
  for r in select value from jsonb_array_elements(coalesce(p->'age_rules','[]')) loop
    if not(p_divisions ? coalesce(r->>'division','')) or r->>'division'=any(ids)
      or coalesce(r->>'min','')!~'^[0-9]+$' or coalesce(r->>'max','')!~'^[0-9]+$'
      or (r->>'min')::integer>(r->>'max')::integer or (r->>'max')::integer>120 then raise exception 'Check the division age ranges.'; end if;
    ids:=array_append(ids,r->>'division');
  end loop;
  ids:='{}';
  if jsonb_typeof(coalesce(p->'sessions','[]'))<>'array' or jsonb_array_length(coalesce(p->'sessions','[]'))>100 then raise exception 'Invalid contest sessions.'; end if;
  for r in select value from jsonb_array_elements(coalesce(p->'sessions','[]')) loop
    if coalesce(r->>'id','')!~'^[a-zA-Z0-9_-]{1,64}$' or r->>'id'=any(ids)
      or length(btrim(coalesce(r->>'name',''))) not between 1 and 120
      or nullif(r->>'starts_at','') is null or nullif(r->>'ends_at','') is null
      or not isfinite((r->>'starts_at')::timestamptz) or not isfinite((r->>'ends_at')::timestamptz)
      or (r->>'ends_at')::timestamptz<=(r->>'starts_at')::timestamptz
      or coalesce(r->>'capacity','0')!~'^[0-9]{1,6}$' then raise exception 'Check session names, dates, and capacities.'; end if;
    ids:=array_append(ids,r->>'id');
  end loop;
  if coalesce((p->>'category_session_capacity')::integer,0)>0 and (
    jsonb_array_length(coalesce(p->'categories','[]'))=0 or
    jsonb_array_length(coalesce(p->'sessions','[]'))=0) then
    raise exception 'Add categories and sessions before setting a category/session limit.';
  end if;
  ids:='{}';
  if jsonb_typeof(coalesce(p->'awards','[]'))<>'array' or jsonb_array_length(coalesce(p->'awards','[]'))>100 then raise exception 'Invalid awards.'; end if;
  for r in select value from jsonb_array_elements(coalesce(p->'awards','[]')) loop
    if length(btrim(coalesce(r->>'name',''))) not between 1 and 120 or lower(btrim(r->>'name'))=any(ids)
      or coalesce(r->>'recipients','1')!~'^[0-9]{1,5}$' or coalesce(r->>'scope','division') not in ('division','contest') then raise exception 'Check award names and recipient limits.'; end if;
    ids:=array_append(ids,lower(btrim(r->>'name')));
  end loop;
  foreach k in array array['checkin_open_at','checkin_close_at','submission_close_at'] loop
    if nullif(p->>k,'') is not null and not isfinite((p->>k)::timestamptz) then raise exception 'Invalid contest date.'; end if;
  end loop;
  if nullif(p->>'checkin_close_at','') is not null and nullif(p->>'checkin_open_at','') is not null
    and (p->>'checkin_close_at')::timestamptz<=(p->>'checkin_open_at')::timestamptz then raise exception 'Check-in must close after it opens.'; end if;
end; $$;

create or replace function show_addons_private.validate_registration_limits(p_cart public.entry_carts,p_offer show_addons_private.offerings,p_ex uuid,p_quantity integer,p_data jsonb,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare used bigint; capacity integer; session jsonb; member jsonb;
begin
  select coalesce(sum(x.quantity),0) into used from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id
    where x.offering_id=p_offer.id and x.exhibitor_id=p_ex and x.id<>p_id and c.status in ('active','submitted');
  if p_quantity is null or p_quantity<1 or p_quantity+used>p_offer.max_per_exhibitor then
    raise exception 'The limit for % is % per exhibitor across the full show.',p_offer.name,p_offer.max_per_exhibitor; end if;
  if p_offer.kind<>'contest' then return; end if;
  if p_quantity<>1 then raise exception 'Register each contestant, team, or project separately.'; end if;
  if coalesce((p_offer.contest_config->>'category_limit')::integer,0)>0 and nullif(p_data->>'category','') is not null then
    select count(*) into used from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id
      where x.offering_id=p_offer.id and x.exhibitor_id=p_ex and x.id<>p_id and c.status in ('active','submitted') and x.registration_data->>'category'=p_data->>'category';
    if used>= (p_offer.contest_config->>'category_limit')::integer then raise exception 'The entry limit for this category has been reached.'; end if;
  end if;
  -- Completed entries and payment reservations hold capacity. Other unsubmitted
  -- carts do not reserve places indefinitely. The offering is locked by callers.
  capacity:=coalesce((p_offer.contest_config->>'capacity')::integer,0);
  if capacity>0 then
    select count(*) into used from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id
      where x.offering_id=p_offer.id and x.id<>p_id and (c.status='submitted' or c.active_payment_session_id is not null or c.id=p_cart.id);
    if used>=capacity then raise exception 'This contest has reached its capacity.'; end if;
  end if;
  select value into session from jsonb_array_elements(coalesce(p_offer.contest_config->'sessions','[]')) where value->>'id'=p_data->>'session_id';
  if coalesce((session->>'capacity')::integer,0)>0 then
    select count(*) into used from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id
      where x.offering_id=p_offer.id and x.id<>p_id and x.registration_data->>'session_id'=p_data->>'session_id'
        and (c.status='submitted' or c.active_payment_session_id is not null or c.id=p_cart.id);
    if used>=(session->>'capacity')::integer then raise exception 'This contest session has reached its capacity.'; end if;
  end if;
  -- All linked shows use the same offering. Capacity is shared across
  -- households/species/divisions, independently for each category/session pair.
  -- Match the existing reservation policy: submitted carts, payment holds,
  -- and all other registrations in this cart count; abandoned drafts do not.
  capacity:=coalesce((p_offer.contest_config->>'category_session_capacity')::integer,0);
  if capacity>0 then
    select count(*) into used from show_addons_private.selections x
      join public.entry_carts c on c.id=x.cart_id
      where x.offering_id=p_offer.id and x.id<>p_id
        and x.registration_data->>'category'=p_data->>'category'
        and x.registration_data->>'session_id'=p_data->>'session_id'
        and (c.status='submitted' or c.active_payment_session_id is not null or c.id=p_cart.id);
    if used>=capacity then
      raise exception 'This category has reached its limit of % entries for this session. Choose another category or session.',capacity;
    end if;
  end if;
  if p_offer.contest_config->>'entry_type'='team' then
    for member in select value from jsonb_array_elements(p_data#>'{team,members}') loop
      if exists(select 1 from show_addons_private.selections x join public.entry_carts c on c.id=x.cart_id,
        lateral jsonb_array_elements(coalesce(x.registration_data#>'{team,members}','[]')) m
        where x.offering_id=p_offer.id and x.id<>p_id and c.status in ('active','submitted')
          and lower(btrim(m->>'name'))=lower(btrim(member->>'name')) and m->>'birthdate'=member->>'birthdate') then
        raise exception 'A member is already registered on another team in this contest.';
      end if;
    end loop;
  end if;
end; $$;
