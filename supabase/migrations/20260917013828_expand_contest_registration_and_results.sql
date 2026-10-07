-- Configurable registrations and staff-entered contest results. Existing
-- offerings keep their behavior when contest_config is empty.
alter table show_addons_private.offerings
  drop constraint offerings_check,
  add column contest_config jsonb not null default '{}',
  add column results_published_at timestamptz;
alter table show_addons_private.selections
  drop constraint selections_cart_id_offering_id_exhibitor_id_key,
  add column registration_data jsonb not null default '{}',
  add column config_snapshot jsonb not null default '{}';
create index contest_selection_scope on show_addons_private.selections
  (offering_id,division,(registration_data->>'category'),(registration_data->>'session_id'));

create table show_addons_private.contest_operations (
  selection_id uuid primary key references show_addons_private.selections(id) on delete cascade,
  checked_in boolean not null default false,
  checked_in_at timestamptz,
  approval_status text not null default 'accepted' check(approval_status in ('pending','accepted','waitlisted','declined')),
  result jsonb not null default '{"status":"pending","awards":[]}',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
create table show_addons_private.contest_history (
  id bigint generated always as identity primary key,
  offering_id uuid not null references show_addons_private.offerings(id),
  selection_id uuid references show_addons_private.selections(id) on delete set null,
  actor_id uuid not null references auth.users(id),
  action text not null, before_value jsonb, after_value jsonb,
  reason text not null default '', created_at timestamptz not null default now()
);
create index contest_history_offering on show_addons_private.contest_history(offering_id,created_at);
create table show_addons_private.contest_drafts (
  id uuid primary key,
  cart_id uuid not null references public.entry_carts(id) on delete cascade,
  offering_id uuid not null references show_addons_private.offerings(id),
  exhibitor_id uuid not null references public.exhibitors(id),
  data jsonb not null, updated_at timestamptz not null default now()
);
create index contest_drafts_cart on show_addons_private.contest_drafts(cart_id);
alter table show_addons_private.contest_operations enable row level security;
alter table show_addons_private.contest_history enable row level security;
alter table show_addons_private.contest_drafts enable row level security;
revoke all on show_addons_private.contest_operations,show_addons_private.contest_history,show_addons_private.contest_drafts from public,anon,authenticated;

create function show_addons_private.string_list(p_value jsonb,p_label text,p_max integer default 100)
returns void language plpgsql security invoker set search_path='' as $$
begin
  if jsonb_typeof(p_value) is distinct from 'array' or jsonb_array_length(p_value)>p_max
    or exists(select 1 from jsonb_array_elements(p_value) v where jsonb_typeof(v)<>'string' or length(btrim(v#>>'{}')) not between 1 and 120)
    or (select count(*)<>count(distinct btrim(value#>>'{}')) from jsonb_array_elements(p_value)) then
    raise exception '% must contain unique, nonempty names.',p_label;
  end if;
end; $$;

create function show_addons_private.validate_config(p jsonb,p_divisions jsonb)
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
  foreach k in array array['capacity','category_limit','max_awarded_per_exhibitor','places','team_min','team_max','team_alternates'] loop
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

-- Conditional fields are filtered before answer validation. File access itself
-- is checked against Storage plus the authorized registration context below.
create or replace function show_addons_private.validate_fields(p_fields jsonb,p_answers jsonb default null)
returns void language plpgsql security invoker set search_path='' as $$
declare f jsonb; a jsonb; t text; ids text[]:='{}'; maximum integer;
begin
  if jsonb_typeof(p_fields) is distinct from 'array' or jsonb_array_length(p_fields)>40 then raise exception 'Use at most 40 contest fields.'; end if;
  if p_answers is not null and (jsonb_typeof(p_answers)<>'object' or length(p_answers::text)>500000) then raise exception 'Invalid contest answers.'; end if;
  for f in select value from jsonb_array_elements(p_fields) loop
    if jsonb_typeof(f)<>'object' or coalesce(f->>'id','')!~'^[a-zA-Z0-9_-]{1,64}$' or f->>'id'=any(ids)
      or length(btrim(coalesce(f->>'label',''))) not between 1 and 120
      or coalesce(f->>'type','') not in ('text','long_text','number','date','checkbox','select','multi_select','url','file')
      or jsonb_typeof(f->'required') is distinct from 'boolean' then raise exception 'Each field needs a unique ID, label, type, and required setting.'; end if;
    ids:=array_append(ids,f->>'id'); maximum:=coalesce((f->>'max_length')::integer,2000);
    if maximum not between 1 and 20000 then raise exception 'Answer limits must be between 1 and 20,000 characters.'; end if;
    if f->>'type' in ('select','multi_select') then
      perform show_addons_private.string_list(coalesce(f->'options','[]'),'Dropdown choices');
      if jsonb_array_length(f->'options')=0 then raise exception 'Dropdown choices must be unique, nonempty text.'; end if;
    end if;
    if p_answers is null then continue; end if;
    a:=p_answers->(f->>'id'); t:=btrim(coalesce(a#>>'{}',''));
    if (f->>'required')::boolean and (t='' or a='null'::jsonb or a='[]'::jsonb or
      (f->>'type'='checkbox' and a is distinct from 'true'::jsonb)) then raise exception '% is required.',f->>'label'; end if;
    if a is null or a='null'::jsonb or t='' then continue; end if;
    if f->>'type'='file' then
      if jsonb_typeof(a)<>'object' or length(coalesce(a->>'path','')) not between 1 and 500
        or length(coalesce(a->>'name','')) not between 1 and 255 then raise exception 'Upload a file for %.',f->>'label'; end if;
      continue;
    end if;
    if f->>'type'='multi_select' then
      perform show_addons_private.string_list(a,f->>'label');
      if exists(select 1 from jsonb_array_elements_text(a) v where not(f->'options' ? v)) then raise exception 'Choose valid options for %.',f->>'label'; end if;
      continue;
    end if;
    if length(t)>maximum or jsonb_typeof(a) not in ('string','number','boolean') then raise exception 'Invalid answer for %.',f->>'label'; end if;
    if f->>'type'='checkbox' and jsonb_typeof(a)<>'boolean' then raise exception '% must be a checkbox value.',f->>'label'; end if;
    if f->>'type'='number' and t!~'^-?[0-9]+(\.[0-9]+)?$' then raise exception '% must be a number.',f->>'label'; end if;
    if f->>'type'='date' and (t!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or to_char(t::date,'YYYY-MM-DD')<>t) then raise exception '% must be a valid date.',f->>'label'; end if;
    if f->>'type'='select' and not(f->'options' ? t) then raise exception 'Choose a valid option for %.',f->>'label'; end if;
    if f->>'type'='url' and t!~'^https?://[^/[:space:]]+([/?#][^[:space:]]*)?$' then raise exception 'Enter a full web link for %.',f->>'label'; end if;
  end loop;
  if p_answers is not null and exists(select 1 from jsonb_object_keys(p_answers) k where not k=any(ids)) then raise exception 'The form has changed. Reload it before continuing.'; end if;
end; $$;

create function show_addons_private.effective_fields(p_fields jsonb,p_data jsonb,p_division text)
returns jsonb language sql immutable set search_path='' as $$
  select coalesce(jsonb_agg(value),'[]') from jsonb_array_elements(p_fields)
  where (coalesce(value->>'only_category','')='' or value->>'only_category'=p_data->>'category')
    and (coalesce(value->>'only_division','')='' or value->>'only_division'=p_division);
$$;

create function show_addons_private.registration_data(p_cart public.entry_carts,p_offer show_addons_private.offerings,p_ex uuid,p_data jsonb,p_division text)
returns jsonb language plpgsql security definer set search_path='' as $$
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
    when 'show_end' then s.end_date else s.start_date end into cutoff from public.shows s where s.id=p_cart.show_id;
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
        where x.offering_id=(cfg->>'prerequisite_contest_id')::uuid and x.show_id=p_cart.show_id
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
        select value into snapshot from jsonb_array_elements(show_addons_private.animal_choices(p_cart,p_ex)) where value->>'key'=a->>'key';
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
end; $$;

create or replace function show_addons_private.save_offering(p_show_id uuid,p_item jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_item->>'id')::uuid; existing show_addons_private.offerings%rowtype;
begin
  if exists(select 1 from jsonb_array_elements(coalesce(p_item->'fields','[]')) f
    where (nullif(f->>'only_category','') is not null and not(coalesce(p_item#>'{contest_config,categories}','[]') ? (f->>'only_category')))
       or (nullif(f->>'only_division','') is not null and not(coalesce(p_item->'divisions','[]') ? (f->>'only_division')))) then
    raise exception 'A conditional question refers to a category or division that is not configured.';
  end if;
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
  if not (p_item ? 'contest_config') and existing.id is not null then
    p_item:=p_item||jsonb_build_object('contest_config',existing.contest_config,'max_per_exhibitor',existing.max_per_exhibitor);
  end if;
  perform show_addons_private.validate_config(coalesce(p_item->'contest_config','{}'),coalesce(p_item->'divisions','[]'));
  if exists(select 1 from jsonb_array_elements(coalesce(p_item->'fields','[]')) f
    where (nullif(f->>'only_category','') is not null and not(coalesce(p_item#>'{contest_config,categories}','[]') ? (f->>'only_category')))
       or (nullif(f->>'only_division','') is not null and not(coalesce(p_item->'divisions','[]') ? (f->>'only_division')))) then
    raise exception 'A conditional question refers to a category or division that is not configured.';
  end if;
  if p_item->>'kind'<>'contest' and coalesce(p_item->'contest_config','{}')<>'{}'::jsonb then raise exception 'Contest settings are only available for contests.'; end if;
  if nullif(p_item#>>'{contest_config,prerequisite_contest_id}','') is not null and not exists(
    select 1 from show_addons_private.offerings o where o.id=(p_item#>>'{contest_config,prerequisite_contest_id}')::uuid
      and o.id<>v_id and o.show_id=p_show_id and o.kind='contest' and coalesce(o.contest_config->>'entry_type','individual')='individual') then
    raise exception 'Choose an individual contest from this show as the prerequisite.';
  end if;
  if existing.results_published_at is not null and
    (existing.divisions,existing.contest_config) is distinct from (coalesce(p_item->'divisions','[]'),coalesce(p_item->'contest_config','{}')) then
    raise exception 'Reopen published results before changing contest rules.';
  end if;
  if found and (existing.show_id<>p_show_id or existing.kind<>p_item->>'kind') then raise exception 'This item belongs to a different show or type.' using errcode='42501'; end if;
  if p_item->>'kind'='extra' and jsonb_array_length(coalesce(p_item->'fields','[]'))>0 then raise exception 'Add-on items do not use contest fields.'; end if;
  insert into show_addons_private.offerings(id,show_id,kind,name,description,price_cents,enabled,requires_animal_entry,max_per_exhibitor,fields,divisions,animal_selection,use_show_entry_dates,registration_open_at,registration_close_at,contest_config)
    values(v_id,p_show_id,p_item->>'kind',btrim(p_item->>'name'),coalesce(p_item->>'description',''),(p_item->>'price_cents')::integer,
      coalesce((p_item->>'enabled')::boolean,true),coalesce((p_item->>'requires_animal_entry')::boolean,false),
      coalesce((p_item->>'max_per_exhibitor')::integer,case when p_item->>'kind'='contest' then 1 else 99 end),coalesce(p_item->'fields','[]'),
      coalesce((select jsonb_agg(btrim(value#>>'{}')) from jsonb_array_elements(coalesce(p_item->'divisions','[]'))),'[]'),coalesce(p_item->>'animal_selection','none'),
      coalesce((p_item->>'use_show_entry_dates')::boolean,true),
      case when not coalesce((p_item->>'use_show_entry_dates')::boolean,true) then (p_item->>'registration_open_at')::timestamptz end,
      case when not coalesce((p_item->>'use_show_entry_dates')::boolean,true) then (p_item->>'registration_close_at')::timestamptz end,coalesce(p_item->'contest_config','{}'))
  on conflict(id) do update set name=excluded.name,description=excluded.description,price_cents=excluded.price_cents,
    enabled=excluded.enabled,requires_animal_entry=excluded.requires_animal_entry,max_per_exhibitor=excluded.max_per_exhibitor,
    fields=excluded.fields,divisions=excluded.divisions,animal_selection=excluded.animal_selection,use_show_entry_dates=excluded.use_show_entry_dates,
    registration_open_at=excluded.registration_open_at,registration_close_at=excluded.registration_close_at,contest_config=excluded.contest_config,updated_at=now()
    where offerings.show_id=p_show_id and offerings.kind=excluded.kind;
  if not found then raise exception 'This item belongs to a different show or type.' using errcode='42501'; end if;
  return v_id;
end;
$$;

create function show_addons_private.validate_registration_limits(p_cart public.entry_carts,p_offer show_addons_private.offerings,p_ex uuid,p_quantity integer,p_data jsonb,p_id uuid)
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

create function show_addons_private.validate_uploads(p_offer uuid,p_owner uuid,p_fields jsonb,p_answers jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare f jsonb; path text;
begin
  for f in select value from jsonb_array_elements(p_fields) where value->>'type'='file' loop
    path:=p_answers#>>array[f->>'id','path'];
    if path is null then continue; end if;
    if split_part(path,'/',1)<>p_offer::text or not exists(
      select 1 from storage.objects o where o.bucket_id='contest-submissions' and o.name=path
        and (split_part(o.name,'/',2)=p_owner::text or split_part(o.name,'/',2)=auth.uid()::text
          or household_private.has_access(split_part(o.name,'/',2)::uuid))) then
      raise exception 'The attachment is unavailable or belongs to another registration.' using errcode='42501';
    end if;
  end loop;
end; $$;

create function show_addons_private.save_registration(p_cart_id uuid,p_offering_id uuid,p_exhibitor_id uuid,p_quantity integer,p_answers jsonb,p_division text,p_animal_key text,p_data jsonb,p_id uuid,p_staff boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
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
    values(v_registration_id,o.id,c.show_id,c.id,p_exhibitor_id,carrier,p_quantity,o.price_cents,o.name,o.kind,fields,p_answers,p_division,p_animal_key,animal,data,o.contest_config)
    on conflict on constraint selections_pkey do update set quantity=excluded.quantity,unit_price_cents=excluded.unit_price_cents,
      name=excluded.name,fields=excluded.fields,answers=excluded.answers,division=excluded.division,animal_key=excluded.animal_key,
      animal_snapshot=excluded.animal_snapshot,registration_data=excluded.registration_data,config_snapshot=excluded.config_snapshot,updated_at=now();
  delete from show_addons_private.contest_drafts where contest_drafts.id=v_registration_id and cart_id=c.id;
  perform show_addons_private.refresh_cart(c.id);
  return v_registration_id;
end; $$;

-- Old clients retain idempotent single-registration editing.
create or replace function show_addons_private.save_selection(p_cart_id uuid,p_offering_id uuid,p_exhibitor_id uuid,p_quantity integer,p_answers jsonb,p_division text default null,p_animal_key text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid;
begin
  perform show_addons_private.assert_cart(p_cart_id,true);
  select s.id into id from show_addons_private.selections s where s.cart_id=p_cart_id and s.offering_id=p_offering_id and s.exhibitor_id=p_exhibitor_id order by created_at limit 1;
  return show_addons_private.save_registration(p_cart_id,p_offering_id,p_exhibitor_id,p_quantity,p_answers,p_division,p_animal_key,'{}',id);
end; $$;

create or replace function show_addons_private.validate_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; r record; o show_addons_private.offerings%rowtype; choices show_addons_private.offerings%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart;
  if exists(select 1 from show_addons_private.selections where cart_id=p_cart)
    and exists(select 1 from public.entry_cart_items where cart_id=p_cart and not is_show_addon_carrier)
    and exists(select 1 from public.shows where id=c.show_id and (entry_open_at>now() or entry_close_at<now())) then
    raise exception 'Remove animal entries from the cart to register for contests outside the show entry window.';
  end if;
  -- Acquire offering locks consistently for mixed-contest carts.
  perform 1 from show_addons_private.offerings where id in (select offering_id from show_addons_private.selections where cart_id=p_cart) order by id for update;
  for r in select * from show_addons_private.selections where cart_id=p_cart order by offering_id,id loop
    select * into o from show_addons_private.offerings where id=r.offering_id;
    if o.results_published_at is not null then raise exception 'Registration is closed because results have been published.'; end if;
    perform show_addons_private.assert_eligible(c,o,r.exhibitor_id);
    choices:=o;
    if jsonb_array_length(coalesce(o.contest_config->'animal_sources','[]'))>0 or jsonb_array_length(coalesce(o.contest_config->'animal_roles','[]'))>0 then choices.animal_selection:='none'; end if;
    perform show_addons_private.validate_choices(c,choices,r.exhibitor_id,r.division,r.animal_key);
    perform show_addons_private.registration_data(c,o,r.exhibitor_id,r.registration_data,r.division);
    perform show_addons_private.validate_registration_limits(c,o,r.exhibitor_id,r.quantity,r.registration_data,r.id);
    perform show_addons_private.validate_fields(r.fields,r.answers);
    perform show_addons_private.validate_uploads(o.id,c.user_id,r.fields,r.answers);
    if nullif(o.contest_config->>'submission_close_at','') is not null and (o.contest_config->>'submission_close_at')::timestamptz<now() then raise exception 'The submission deadline has passed.'; end if;
  end loop;
end; $$;

create function show_addons_private.save_draft(p_cart uuid,p_offer uuid,p_ex uuid,p_id uuid,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; o show_addons_private.offerings%rowtype; existing show_addons_private.contest_drafts%rowtype;
begin
  c:=show_addons_private.assert_cart(p_cart,true);
  select * into o from show_addons_private.offerings where id=p_offer;
  perform show_addons_private.assert_eligible(c,o,p_ex);
  if o.kind<>'contest' or jsonb_typeof(p_data) is distinct from 'object' or length(p_data::text)>550000 then raise exception 'Invalid contest draft.'; end if;
  select * into existing from show_addons_private.contest_drafts where id=p_id for update;
  if found and (existing.cart_id,existing.offering_id,existing.exhibitor_id) is distinct from (p_cart,p_offer,p_ex) then raise exception 'Draft access denied.' using errcode='42501'; end if;
  if exists(select 1 from show_addons_private.selections where id=p_id) then raise exception 'This entry is already in the cart. Edit it there.'; end if;
  insert into show_addons_private.contest_drafts(id,cart_id,offering_id,exhibitor_id,data) values(p_id,p_cart,p_offer,p_ex,p_data)
    on conflict(id) do update set data=excluded.data,updated_at=now();
  return p_id;
end; $$;
create function show_addons_private.drafts(p_cart uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform show_addons_private.assert_cart(p_cart);
  return coalesce((select jsonb_agg(to_jsonb(d)) from show_addons_private.contest_drafts d where cart_id=p_cart),'[]');
end; $$;

create function show_addons_private.upload_access(p_path text,p_write boolean default false)
returns boolean language plpgsql security definer set search_path='' as $$
declare offering uuid; uploader uuid; v_show_id uuid;
begin
  if auth.uid() is null then return false; end if;
  begin offering:=split_part(p_path,'/',1)::uuid; uploader:=split_part(p_path,'/',2)::uuid; exception when invalid_text_representation then return false; end;
  select o.show_id into v_show_id from show_addons_private.offerings o where o.id=offering and o.kind='contest';
  if v_show_id is null then return false; end if;
  if p_write then return uploader=auth.uid() and exists(select 1 from public.shows s where s.id=v_show_id and
    ((s.is_published and s.contests_enabled) or public.user_can_manage_show_settings(s.id)))
    and p_path ~ '^[0-9a-f-]+/[0-9a-f-]+/[0-9a-f-]+\.(pdf|png|jpg|jpeg)$'; end if;
  if uploader=auth.uid() or household_private.has_access(uploader) then return true; end if;
  return exists(
    select 1 from show_addons_private.selections r join public.entry_carts c on c.id=r.cart_id,
      lateral jsonb_each(r.answers) a where r.offering_id=offering and c.status='submitted' and a.value->>'path'=p_path
        and (public.user_can_manage_show_settings(v_show_id) or household_private.has_access(c.user_id)));
end; $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('contest-submissions','contest-submissions',false,10485760,array['application/pdf','image/png','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy contest_submission_insert on storage.objects for insert to authenticated
  with check(bucket_id='contest-submissions' and show_addons_private.upload_access(name,true));
create policy contest_submission_read on storage.objects for select to authenticated
  using(bucket_id='contest-submissions' and show_addons_private.upload_access(name,false));
-- Restrictive guards also protect this bucket if a deployment has broader
-- legacy permissive Storage policies for unrelated public assets.
create policy contest_submission_read_guard on storage.objects as restrictive for select to public
  using(bucket_id<>'contest-submissions' or show_addons_private.upload_access(name,false));
create policy contest_submission_insert_guard on storage.objects as restrictive for insert to public
  with check(bucket_id<>'contest-submissions' or show_addons_private.upload_access(name,true));
create policy contest_submission_update_guard on storage.objects as restrictive for update to public
  using(bucket_id<>'contest-submissions') with check(bucket_id<>'contest-submissions');
create policy contest_submission_delete_guard on storage.objects as restrictive for delete to public
  using(bucket_id<>'contest-submissions');
-- Uploads are immutable. Submitted files cannot be silently replaced or removed.

create function show_addons_private.operation(p_selection uuid,p_changes jsonb,p_reason text default '',p_expected_at timestamptz default null)
returns void language plpgsql security definer set search_path='' as $$
declare r show_addons_private.selections%rowtype; o show_addons_private.offerings%rowtype;
  previous show_addons_private.contest_operations%rowtype; v_result jsonb; v_approval text; v_checkin boolean;
  award text; rule jsonb; total integer; result_changed boolean; other record;
begin
  select * into r from show_addons_private.selections where id=p_selection;
  if not found or r.kind<>'contest' then raise exception 'Contest registration not found.'; end if;
  perform show_addons_private.assert_secretary(r.show_id);
  select * into o from show_addons_private.offerings where id=r.offering_id for update;
  if not exists(select 1 from public.entry_carts where id=r.cart_id and status='submitted') then raise exception 'Finish registration before managing check-in or results.'; end if;
  select * into previous from show_addons_private.contest_operations where selection_id=r.id for update;
  if p_expected_at is not null and previous.updated_at is distinct from p_expected_at then raise exception 'This registration changed. Reload before saving.'; end if;
  v_result:=coalesce(p_changes->'result',previous.result,'{"status":"pending","awards":[]}');
  v_approval:=coalesce(p_changes->>'approval_status',previous.approval_status,case when coalesce((r.config_snapshot->>'requires_approval')::boolean,false) then 'pending' else 'accepted' end);
  v_checkin:=coalesce((p_changes->>'checked_in')::boolean,previous.checked_in,false);
  if p_changes ? 'result' and not coalesce((o.contest_config->>'results_enabled')::boolean,true) then raise exception 'Enable contest results in setup first.'; end if;
  result_changed:=v_result is distinct from coalesce(previous.result,'{"status":"pending","awards":[]}'::jsonb);
  if (result_changed or v_approval is distinct from previous.approval_status) and o.results_published_at is not null then raise exception 'Reopen published results before making corrections.'; end if;
  if v_approval not in ('pending','accepted','waitlisted','declined') then raise exception 'Invalid approval status.'; end if;
  if v_checkin and v_approval<>'accepted' then raise exception 'Accept this registration before checking it in.'; end if;
  if jsonb_typeof(v_result)<>'object' or coalesce(v_result->>'status','') not in ('pending','recorded','absent','withdrawn','disqualified','finalist') then raise exception 'Choose a valid result status.'; end if;
  if nullif(v_result->>'place','') is not null and (v_result->>'place'!~'^[0-9]{1,4}$' or (v_result->>'place')::integer not between 1 and coalesce((o.contest_config->>'places')::integer,20)) then raise exception 'Enter a placing within this contest’s configured places.'; end if;
  perform show_addons_private.string_list(coalesce(v_result->'awards','[]'),'Awards');
  if length(coalesce(v_result->>'ribbon',''))>120 then raise exception 'Ribbon name is too long.'; end if;
  if (nullif(v_result->>'place','') is not null or coalesce(v_result->'awards','[]')<>'[]'::jsonb or nullif(v_result->>'ribbon','') is not null)
    and (v_result->>'status'<>'recorded' or v_approval<>'accepted') then raise exception 'Only accepted, recorded results can receive a placing or award.'; end if;
  v_result:=jsonb_build_object('status',v_result->>'status','place',nullif(v_result->>'place','')::integer,
    'awards',coalesce(v_result->'awards','[]'),'ribbon',coalesce(v_result->>'ribbon',''));
  if result_changed and previous.result->>'status' is not null and previous.result->>'status'<>'pending' and length(btrim(p_reason))=0 then raise exception 'Enter a reason for the result correction.'; end if;
  for other in select x.*,ops.result from show_addons_private.selections x join show_addons_private.contest_operations ops on ops.selection_id=x.id
    where x.offering_id=o.id and x.id<>r.id and ops.result->>'status'='recorded' loop
    if (coalesce(other.division,''),coalesce(other.registration_data->>'category',''),coalesce(other.registration_data->>'session_id',''))=
       (coalesce(r.division,''),coalesce(r.registration_data->>'category',''),coalesce(r.registration_data->>'session_id',''))
      and nullif(v_result->>'place','') is not null and other.result->>'place'=v_result->>'place'
      and not coalesce((o.contest_config->>'allow_ties')::boolean,false) then raise exception 'That place is already assigned in this division/category/session.'; end if;
  end loop;
  for award in select value from jsonb_array_elements_text(v_result->'awards') loop
    select value into rule from jsonb_array_elements(coalesce(o.contest_config->'awards','[]')) where value->>'name'=award;
    if jsonb_array_length(coalesce(o.contest_config->'awards','[]'))>0 and rule is null then raise exception 'Choose one of the contest’s configured awards.'; end if;
    if coalesce((rule->>'recipients')::integer,1)>0 then
      select count(*) into total from show_addons_private.selections x join show_addons_private.contest_operations ops on ops.selection_id=x.id
      where x.offering_id=o.id and x.id<>r.id and ops.result->'awards' ? award and
        (coalesce(rule->>'scope','division')='contest' or
         (coalesce(x.division,''),coalesce(x.registration_data->>'category',''),coalesce(x.registration_data->>'session_id',''))=
         (coalesce(r.division,''),coalesce(r.registration_data->>'category',''),coalesce(r.registration_data->>'session_id','')));
      if total>=coalesce((rule->>'recipients')::integer,1) then raise exception 'The recipient limit for award % has been reached.',award; end if;
    end if;
  end loop;
  if coalesce((o.contest_config->>'max_awarded_per_exhibitor')::integer,0)>0 and
    (v_result->>'place' is not null or jsonb_array_length(v_result->'awards')>0) then
    select count(*) into total from show_addons_private.selections x join show_addons_private.contest_operations ops on ops.selection_id=x.id
      where x.offering_id=o.id and x.id<>r.id and x.exhibitor_id=r.exhibitor_id
        and coalesce(x.registration_data->>'category','')=coalesce(r.registration_data->>'category','')
        and (ops.result->>'place' is not null or jsonb_array_length(coalesce(ops.result->'awards','[]'))>0);
    if total>=(o.contest_config->>'max_awarded_per_exhibitor')::integer then raise exception 'This exhibitor has reached the award limit in this category.'; end if;
  end if;
  insert into show_addons_private.contest_operations(selection_id,checked_in,checked_in_at,approval_status,result,updated_by)
    values(r.id,v_checkin,case when v_checkin then coalesce(previous.checked_in_at,now()) end,v_approval,v_result,auth.uid())
    on conflict(selection_id) do update set checked_in=excluded.checked_in,checked_in_at=excluded.checked_in_at,approval_status=excluded.approval_status,
      result=excluded.result,updated_at=clock_timestamp(),updated_by=auth.uid();
  insert into show_addons_private.contest_history(offering_id,selection_id,actor_id,action,before_value,after_value,reason)
    values(o.id,r.id,auth.uid(),'update',to_jsonb(previous),jsonb_build_object('checked_in',v_checkin,'approval_status',v_approval,'result',v_result),left(p_reason,2000));
end; $$;

create function show_addons_private.publish_results(p_offering uuid,p_publish boolean,p_reason text default '')
returns void language plpgsql security definer set search_path='' as $$
declare o show_addons_private.offerings%rowtype;
begin
  select * into o from show_addons_private.offerings where id=p_offering for update;
  if not found or o.kind<>'contest' then raise exception 'Contest not found.'; end if;
  perform show_addons_private.assert_secretary(o.show_id);
  if not coalesce((o.contest_config->>'results_enabled')::boolean,true) then raise exception 'Enable contest results in setup first.'; end if;
  if not p_publish and o.results_published_at is not null and length(btrim(p_reason))=0 then raise exception 'Enter a reason to reopen results.'; end if;
  if p_publish then
    if o.results_published_at is not null then return; end if;
    if exists(select 1 from show_addons_private.selections r join public.entry_carts c on c.id=r.cart_id
      left join show_addons_private.contest_operations ops on ops.selection_id=r.id
      where r.offering_id=o.id and c.status='submitted'
        and coalesce(ops.approval_status,case when coalesce((r.config_snapshot->>'requires_approval')::boolean,false) then 'pending' else 'accepted' end)='accepted'
        and coalesce(ops.result->>'status','pending')='pending') then
      raise exception 'Record a result status for every accepted registration before publishing.';
    end if;
  end if;
  update show_addons_private.offerings set results_published_at=case when p_publish then now() end where id=o.id;
  insert into show_addons_private.contest_history(offering_id,actor_id,action,reason)
    values(o.id,auth.uid(),case when p_publish then 'publish' else 'reopen' end,left(p_reason,2000));
end; $$;

create or replace function show_addons_private.registrations(p_show_id uuid default null,p_owner_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to view registrations.' using errcode='42501'; end if;
  if p_show_id is not null then
    if not public.user_can_manage_show_settings(p_show_id) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  elsif p_owner_id is null or not household_private.has_access(p_owner_id) then raise exception 'Household access is required.' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('show_name',s.name,'exhibitor_name',coalesce(nullif(e.showing_name,''),e.display_name),
    'exhibitor_number',e.exhibitor_number,'email',e.email,'payment_status',coalesce(b.payment_status,c.payment_status),
    'currency',coalesce(b.currency,c.currency,'usd'),'checked_in',coalesce(ops.checked_in,false),'checked_in_at',ops.checked_in_at,
    'approval_status',coalesce(ops.approval_status,case when coalesce((r.config_snapshot->>'requires_approval')::boolean,false) then 'pending' else 'accepted' end),
    'result',case when p_show_id is not null or o.results_published_at is not null then ops.result end,
    'operation_updated_at',ops.updated_at,'results_published_at',o.results_published_at)
    order by s.start_date,r.created_at,r.id)
    from show_addons_private.selections r join public.entry_carts c on c.id=r.cart_id join public.shows s on s.id=r.show_id
    join show_addons_private.offerings o on o.id=r.offering_id join public.exhibitors e on e.id=r.exhibitor_id
    left join show_addons_private.contest_operations ops on ops.selection_id=r.id
    left join public.show_exhibitor_balances b on b.entry_cart_id=r.cart_id and b.exhibitor_id=r.exhibitor_id and b.source='cart'
    where c.status='submitted' and case when p_show_id is not null then r.show_id=p_show_id else c.user_id=p_owner_id end),'[]');
end; $$;

-- Results-only export deliberately excludes birthdates, contacts, documents,
-- answers, and unpublished results, even for other signed-in households.
create function show_addons_private.results(p_show uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'Sign in to view results.' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'offering_id',o.id,'name',r.name,'division',r.division,
      'exhibitor_name',coalesce(nullif(e.showing_name,''),e.display_name),'exhibitor_number',e.exhibitor_number,
      'category',r.registration_data->>'category','session',r.registration_data->>'session_name',
      'team_name',r.registration_data#>>'{team,name}','team_members',(select jsonb_agg(jsonb_build_object('name',m->>'name','alternate',coalesce((m->>'alternate')::boolean,false))) from jsonb_array_elements(coalesce(r.registration_data#>'{team,members}','[]')) m),'project_title',r.registration_data->>'project_title','result',ops.result)
      order by lower(r.name),r.division,r.registration_data->>'category',(ops.result->>'place')::integer nulls last)
    from show_addons_private.selections r join public.entry_carts c on c.id=r.cart_id
    join show_addons_private.offerings o on o.id=r.offering_id join public.shows s on s.id=o.show_id
    join public.exhibitors e on e.id=r.exhibitor_id join show_addons_private.contest_operations ops on ops.selection_id=r.id
    where s.id=p_show and s.is_published and c.status='submitted' and o.results_published_at is not null),'[]');
end; $$;

create function show_addons_private.history(p_offering uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare show uuid;
begin
  select show_id into show from show_addons_private.offerings where id=p_offering;
  if auth.uid() is null or not public.user_can_manage_show_settings(show) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc,h.id desc) from show_addons_private.contest_history h where offering_id=p_offering),'[]');
end; $$;

-- Secretary-entered walk-up registrations use the same eligibility and price
-- validation. They create an unpaid balance, never an external payment.
create function show_addons_private.walkup_context(p_offer uuid,p_number bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o show_addons_private.offerings%rowtype; e public.exhibitors%rowtype; c public.entry_carts%rowtype;
begin
  select * into o from show_addons_private.offerings where id=p_offer;
  perform show_addons_private.assert_secretary(o.show_id);
  if o.kind<>'contest' or not coalesce((o.contest_config->>'allow_walkup')::boolean,false) then raise exception 'Enable walk-up registrations in this contest’s settings first.'; end if;
  select * into e from public.exhibitors where exhibitor_number=p_number::text and is_active;
  if not found then raise exception 'No active exhibitor has that number.'; end if;
  c.id:=extensions.gen_random_uuid();c.show_id:=o.show_id;c.user_id:=e.owner_user_id;
  return jsonb_build_object('id',e.id,'name',coalesce(nullif(e.showing_name,''),e.display_name),'number',e.exhibitor_number,'animals',show_addons_private.animal_choices(c,e.id));
end; $$;
create function show_addons_private.register_walkup(p_offer uuid,p_ex uuid,p_request uuid,p_answers jsonb,p_division text,p_animal_key text,p_data jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare o show_addons_private.offerings%rowtype; e public.exhibitors%rowtype; c public.entry_carts%rowtype; existing show_addons_private.selections%rowtype; result uuid; total integer;
begin
  select * into o from show_addons_private.offerings where id=p_offer;
  perform show_addons_private.assert_secretary(o.show_id);
  if o.kind<>'contest' or not coalesce((o.contest_config->>'allow_walkup')::boolean,false) then raise exception 'Enable walk-up registrations in this contest’s settings first.'; end if;
  select * into e from public.exhibitors where id=p_ex and is_active;
  if not found then raise exception 'Choose an active exhibitor.'; end if;
  insert into public.entry_carts(id,user_id,show_id) values(p_request,e.owner_user_id,o.show_id) on conflict(id) do nothing;
  select * into c from public.entry_carts where id=p_request for update;
  if c.user_id<>e.owner_user_id or c.show_id<>o.show_id then raise exception 'Invalid registration request.' using errcode='42501'; end if;
  select * into existing from show_addons_private.selections where id=p_request;
  if found then
    if existing.cart_id<>c.id or existing.offering_id<>o.id or existing.exhibitor_id<>e.id then raise exception 'Invalid registration request.' using errcode='42501'; end if;
    return existing.id;
  end if;
  result:=show_addons_private.save_registration(c.id,o.id,e.id,1,p_answers,p_division,p_animal_key,p_data,p_request,true);
  select coalesce(sum(calculated_total_cents),0) into total from public.show_exhibitor_balances where entry_cart_id=c.id;
  update public.entry_carts set status='submitted',submitted_at=now(),payment_status=case when total=0 then 'paid' else 'unpaid' end,
    payment_provider='offline',selected_payment_timing='at_show',updated_at=now() where id=c.id;
  insert into show_addons_private.contest_history(offering_id,selection_id,actor_id,action,after_value)
    values(o.id,result,auth.uid(),'walkup',jsonb_build_object('exhibitor_id',e.id,'amount_cents',total));
  return result;
end; $$;
create function public.get_contest_walkup_exhibitor(p_offering_id uuid,p_exhibitor_number bigint)
returns jsonb language sql security invoker set search_path='' as $$select show_addons_private.walkup_context(p_offering_id,p_exhibitor_number);$$;
create function public.register_contest_walkup(p_offering_id uuid,p_exhibitor_id uuid,p_request_id uuid,p_answers jsonb,p_division text default null,p_animal_key text default null,p_registration_data jsonb default '{}')
returns uuid language sql security invoker set search_path='' as $$select show_addons_private.register_walkup(p_offering_id,p_exhibitor_id,p_request_id,p_answers,p_division,p_animal_key,p_registration_data);$$;

create function public.save_contest_registration(p_cart_id uuid,p_offering_id uuid,p_exhibitor_id uuid,p_quantity integer,p_answers jsonb,p_division text default null,p_animal_key text default null,p_registration_data jsonb default '{}',p_selection_id uuid default null)
returns uuid language sql security invoker set search_path='' as $$ select show_addons_private.save_registration(p_cart_id,p_offering_id,p_exhibitor_id,p_quantity,p_answers,p_division,p_animal_key,p_registration_data,p_selection_id); $$;
create function public.save_contest_draft(p_cart_id uuid,p_offering_id uuid,p_exhibitor_id uuid,p_draft_id uuid,p_data jsonb)
returns uuid language sql security invoker set search_path='' as $$ select show_addons_private.save_draft(p_cart_id,p_offering_id,p_exhibitor_id,p_draft_id,p_data); $$;
create function public.get_contest_drafts(p_cart_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.drafts(p_cart_id); $$;
create function public.update_contest_registration(p_selection_id uuid,p_changes jsonb,p_reason text default '',p_expected_at timestamptz default null)
returns void language sql security invoker set search_path='' as $$ select show_addons_private.operation(p_selection_id,p_changes,p_reason,p_expected_at); $$;
create function public.publish_contest_results(p_offering_id uuid,p_publish boolean,p_reason text default '')
returns void language sql security invoker set search_path='' as $$ select show_addons_private.publish_results(p_offering_id,p_publish,p_reason); $$;
create function public.get_contest_results(p_show_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.results(p_show_id); $$;
create function public.get_contest_history(p_offering_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select show_addons_private.history(p_offering_id); $$;

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
      'effective_age_date',case coalesce(o.contest_config->>'age_as_of','show_start') when 'custom' then (o.contest_config->>'age_date')::date when 'show_end' then s.end_date else s.start_date end,
      'registration_status',case when o.results_published_at is not null then 'closed' when coalesce(s.is_locked,false) or s.finalized_at is not null then 'locked'
        when (case when o.use_show_entry_dates then s.entry_open_at else o.registration_open_at end)>now() then 'upcoming'
        when (case when o.use_show_entry_dates then s.entry_close_at else o.registration_close_at end)<now() then 'closed'
        else 'open' end) order by lower(o.name),o.id),'[]') into items from show_addons_private.offerings o
    where o.show_id=p_show_id and (p_admin or (o.enabled and case when o.kind='contest' then s.contests_enabled else s.extras_enabled end));
  return jsonb_build_object('contests_enabled',s.contests_enabled,'extras_enabled',s.extras_enabled,'items',items,
    'currency',coalesce((select lower(currency) from public.show_fee_settings where show_id=p_show_id),'usd'),
    'entry_open_at',s.entry_open_at,'entry_close_at',s.entry_close_at,'locked',coalesce(s.is_locked,false) or s.finalized_at is not null);
end;
$$;


revoke all on all functions in schema show_addons_private from public,anon,authenticated;
do $$ declare f text; begin
  foreach f in array array[
    'catalog(uuid,boolean)','set_enabled(uuid,text,boolean)','save_offering(uuid,jsonb)',
    'save_selection(uuid,uuid,uuid,integer,jsonb,text,text)','contest_animals(uuid,uuid)','remove_selection(uuid)','cart_items(uuid)',
    'registrations(uuid,uuid)','commit_free(uuid)','open_contest_shows()',
    'save_registration(uuid,uuid,uuid,integer,jsonb,text,text,jsonb,uuid,boolean)',
    'walkup_context(uuid,bigint)','register_walkup(uuid,uuid,uuid,jsonb,text,text,jsonb)',
    'save_draft(uuid,uuid,uuid,uuid,jsonb)','drafts(uuid)','operation(uuid,jsonb,text,timestamp with time zone)',
    'publish_results(uuid,boolean,text)','results(uuid)','history(uuid)','upload_access(text,boolean)'] loop
    execute 'grant execute on function show_addons_private.'||f||' to authenticated,service_role';
  end loop;
  foreach f in array array[
    'save_contest_registration(uuid,uuid,uuid,integer,jsonb,text,text,jsonb,uuid)',
    'save_contest_draft(uuid,uuid,uuid,uuid,jsonb)','get_contest_drafts(uuid)',
    'update_contest_registration(uuid,jsonb,text,timestamp with time zone)','publish_contest_results(uuid,boolean,text)',
    'get_contest_results(uuid)','get_contest_history(uuid)'] loop
    execute 'revoke all on function public.'||f||' from public,anon';
    execute 'grant execute on function public.'||f||' to authenticated,service_role';
  end loop;
end; $$;

revoke all on function public.get_contest_walkup_exhibitor(uuid,bigint),public.register_contest_walkup(uuid,uuid,uuid,jsonb,text,text,jsonb) from public,anon;
grant execute on function public.get_contest_walkup_exhibitor(uuid,bigint),public.register_contest_walkup(uuid,uuid,uuid,jsonb,text,text,jsonb) to authenticated;

grant execute on function show_addons_private.upload_access(text,boolean) to anon;
