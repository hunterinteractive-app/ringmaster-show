-- RingMaster Show schema-only bootstrap for disposable local/staging projects.
-- This is deliberately NOT in supabase/migrations: production already owns
-- these objects and must never attempt to apply this file incrementally.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.report_type as enum (
    'arba_report','legs','checkin_sheet','exhibitor_report',
    'sweepstakes_report','breed_results_detail_report','details_by_breed',
    'exh_by_breed','best_display_report','unpaid_balances_report',
    'paid_exhibitor_report','entered_exhibitors_contact_report',
    'ribbon_payout_report','payback_report','judge_report',
    'breed_judged_totals_report','newsletter_show_report'
  );
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.artifact_status as enum
    ('queued','generating','generated','failed');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.show_task_type as enum
    ('render_report','generate_report','send_email','archive_show');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.show_task_status as enum
    ('queued','claimed','completed','failed','cancelled');
exception when duplicate_object then null; end $$;

create table if not exists public.shows (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null,
  start_date date,
  end_date date,
  location_name text,
  location_address text,
  secretary_name text,
  secretary_email text,
  secretary_phone text,
  secretary_address text,
  club_name text,
  club_id uuid,
  coop_numbering_mode text not null default 'separate',
  created_by uuid,
  is_national_show boolean not null default false,
  national_show_section_id uuid,
  is_test boolean not null default false,
  is_locked boolean not null default false,
  entry_close_at timestamptz,
  results_version bigint not null default 1,
  results_last_changed_at timestamptz default now(),
  payment_timing_mode text not null default 'pay_at_show_only',
  online_payment_fee_mode text not null default 'absorbed',
  online_payment_fee_label text not null default 'Online payment fee',
  online_payment_fee_description text,
  platform_fee_percent numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  id uuid primary key,
  first_name text, last_name text, display_name text,
  email text, phone text, address_line1 text, address_line2 text,
  city text, state text, zip text, arba_number text
);
create table if not exists public.show_managers (
  show_id uuid not null references public.shows(id) on delete cascade,
  user_id uuid not null,
  can_manage_entries boolean not null default true,
  can_manage_settings boolean not null default true,
  can_finalize boolean not null default true,
  primary key (show_id, user_id)
);

create or replace function public.user_can_manage_entries(p_show_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.show_managers m
    where m.show_id=p_show_id and m.user_id=auth.uid() and m.can_manage_entries)
$$;
create or replace function public.user_can_manage_show_settings(p_show_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.show_managers m
    where m.show_id=p_show_id and m.user_id=auth.uid() and m.can_manage_settings)
$$;
create or replace function public.user_can_finalize_show(p_show_id uuid, p_user_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists(select 1 from public.show_managers m
    where m.show_id=p_show_id and m.user_id=p_user_id and m.can_finalize)
$$;

create table if not exists public.breeds (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null, species text not null,
  sort_order integer not null default 0,
  has_varieties boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.variety_groups (
  id uuid primary key default extensions.gen_random_uuid(),
  breed_id uuid not null references public.breeds(id) on delete cascade,
  name text not null, sort_order integer not null default 0
);
create table if not exists public.varieties (
  id uuid primary key default extensions.gen_random_uuid(),
  breed_id uuid not null references public.breeds(id) on delete cascade,
  variety_group_id uuid references public.variety_groups(id) on delete set null,
  group_id uuid references public.variety_groups(id) on delete set null,
  name text not null, sort_order integer not null default 0,
  is_active boolean not null default true
);
create table if not exists public.show_sections (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  kind text not null, letter text not null, display_name text,
  breed_scope text not null default 'all_breed',
  allowed_breed_ids uuid[], is_enabled boolean not null default true,
  sort_order integer not null default 0,
  unique(show_id, kind, letter, display_name)
);

alter table public.shows
  add constraint shows_national_show_section_id_fkey
  foreign key (national_show_section_id)
  references public.show_sections(id)
  on delete set null;

create table if not exists public.exhibitors (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_user_id uuid, exhibitor_user_id uuid,
  created_for_show_id uuid, is_local_only boolean not null default false,
  is_test boolean not null default false,
  exhibitor_number text, showing_name text, display_name text, first_name text, last_name text,
  email text, phone text, type text,
  address_line1 text, address_line2 text, city text, state text, zip text,
  arba_number text, created_at timestamptz not null default now()
);
create table if not exists public.animals (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_user_id uuid, species text, tattoo text, name text, breed text,
  variety text, sex text, class_name text
);
create table if not exists public.entries (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  section_id uuid references public.show_sections(id) on delete set null,
  exhibitor_id uuid references public.exhibitors(id) on delete set null,
  exhibitor_user_id uuid, animal_id uuid,
  species text, tattoo text, animal_name text, breed text, variety text,
  group_name text, fur_variety text, sex text, class_name text,
  status text not null default 'entered', is_shown boolean not null default true,
  is_fur boolean not null default false, is_test boolean not null default false,
  is_disqualified boolean not null default false, scratched_at timestamptz,
  no_show boolean not null default false, coop_number text,
  fur_placement integer,
  payment_status text, paid_at timestamptz,
  judged_by_show_judge_id uuid, placement integer, result_status text,
  disqualified_reason text, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists entries_show_section_idx on public.entries(show_id, section_id);
create index if not exists entries_exhibitor_idx on public.entries(exhibitor_id);

create table if not exists public.entry_awards (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid references public.shows(id) on delete cascade,
  entry_id uuid not null references public.entries(id) on delete cascade,
  award_code text not null, award text, points numeric,
  created_at timestamptz not null default now()
);

-- Legacy reporting RPCs predate the checked-in migration history. Returning
-- JSON objects keeps their field contract stable for Flutter and the headless
-- worker while allowing synthetic local fixtures to stay deliberately small.
create or replace function public.report_results_entry_rows(
  p_show_id uuid,
  p_section_id uuid default null,
  p_show_letter text default null
)
returns setof jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', e.id, 'entry_id', e.id, 'show_id', e.show_id,
    'section_id', e.section_id, 'animal_id', e.animal_id,
    'exhibitor_id', e.exhibitor_id, 'species', e.species,
    'breed', e.breed, 'breed_name', e.breed,
    'variety', e.variety, 'variety_name', e.variety,
    'group_name', e.group_name,
    'uses_group_awards', nullif(btrim(coalesce(e.group_name, '')), '') is not null,
    'tattoo', e.tattoo, 'ear_number', e.tattoo,
    'animal_name', e.animal_name, 'sex', e.sex,
    'class_name', e.class_name, 'fur_variety', e.fur_variety,
    'is_fur', e.is_fur, 'is_shown', e.is_shown,
    'scratched_at', e.scratched_at, 'no_show', e.no_show,
    'is_disqualified', e.is_disqualified,
    'disqualified_reason', e.disqualified_reason,
    'status', e.status, 'result_status', e.result_status,
    'placement', e.placement, 'placing', e.placement,
    'judged_by_show_judge_id', e.judged_by_show_judge_id,
    'notes', e.notes,
    'show_letter', upper(sec.letter), 'section_kind', upper(sec.kind),
    'exhibitor_first_name', ex.first_name,
    'exhibitor_last_name', ex.last_name,
    'exhibitor_display_name', ex.display_name,
    'exhibitor_showing_name', ex.showing_name,
    'exhibitor_label', coalesce(nullif(ex.display_name, ''), btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, ''))),
    'exhibitor_number', ex.exhibitor_number,
    'exhibitor_city', ex.city, 'exhibitor_state', ex.state,
    'exhibitor_arba_number', ex.arba_number
  )
  from public.entries e
  join public.show_sections sec on sec.id = e.section_id
  left join public.exhibitors ex on ex.id = e.exhibitor_id
  where e.show_id = p_show_id
    and (p_section_id is null or e.section_id = p_section_id)
    and (p_show_letter is null or upper(sec.letter) = upper(p_show_letter))
  order by sec.sort_order, e.breed, e.variety, e.class_name, e.sex, e.tattoo
$$;

create or replace function public.report_checkin_entries(
  p_show_id uuid,
  p_section_id uuid default null,
  p_include_scratched boolean default false
)
returns setof jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', e.id, 'entry_id', e.id, 'show_id', e.show_id,
    'section_id', e.section_id, 'animal_id', e.animal_id,
    'exhibitor_id', e.exhibitor_id, 'species', e.species,
    'breed', e.breed, 'breed_name', e.breed,
    'variety', e.variety, 'variety_name', e.variety,
    'group_name', e.group_name, 'tattoo', e.tattoo,
    'animal_name', e.animal_name, 'sex', e.sex,
    'class_name', e.class_name, 'is_fur', e.is_fur,
    'fur_variety', e.fur_variety, 'coop_number', e.coop_number,
    'is_shown', e.is_shown, 'scratched_at', e.scratched_at,
    'show_letter', upper(sec.letter), 'section_kind', upper(sec.kind),
    'section_label', coalesce(sec.display_name, initcap(sec.kind) || ' ' || upper(sec.letter)),
    'exhibitor_number', ex.exhibitor_number,
    'exhibitor_first_name', ex.first_name,
    'exhibitor_last_name', ex.last_name,
    'exhibitor_display_name', ex.display_name,
    'exhibitor_showing_name', ex.showing_name
  )
  from public.entries e
  join public.show_sections sec on sec.id = e.section_id
  left join public.exhibitors ex on ex.id = e.exhibitor_id
  where e.show_id = p_show_id
    and (p_section_id is null or e.section_id = p_section_id)
    and (p_include_scratched or e.scratched_at is null)
  order by sec.sort_order, ex.display_name, e.breed, e.variety, e.tattoo
$$;
create table if not exists public.results (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  entry_id uuid not null references public.entries(id) on delete cascade,
  judge_id uuid, "placing" integer, placing_label text, award text,
  created_at timestamptz not null default now()
);
create table if not exists public.judges (
  id uuid primary key default extensions.gen_random_uuid(),
  name text, first_name text, last_name text, display_name text,
  arba_number text, arba_judge_number text,
  email text, phone text
);
create table if not exists public.show_judges (
  show_id uuid not null references public.shows(id) on delete cascade,
  judge_id uuid not null references public.judges(id) on delete cascade,
  section_id uuid references public.show_sections(id) on delete set null,
  sort_order integer not null default 0, is_enabled boolean not null default true,
  primary key(show_id, judge_id, section_id)
);
create table if not exists public.judge_assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid references public.shows(id) on delete cascade,
  judge_id uuid references public.judges(id), section_id uuid references public.show_sections(id),
  breed_id uuid references public.breeds(id), breed_name text, sort_order integer default 0
);

create table if not exists public.clubs (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null, club_name text, email text, mailing_address text
);
create table if not exists public.show_sanctions (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  section_id uuid references public.show_sections(id) on delete cascade,
  breed_name text, club_name text, club_id uuid references public.clubs(id),
  sanction_number text, sanctioning_body text not null,
  sweepstakes_email text, created_at timestamptz not null default now()
);
create table if not exists public.show_arba_report_details (
  show_id uuid primary key references public.shows(id) on delete cascade,
  club_name text, club_number text, secretary_name text, secretary_email text,
  secretary_phone text, superintendent_name text, superintendent_email text,
  location text, district text, report_notes text,
  secretary_address text, superintendent_arba_number text,
  sweepstakes_issue boolean not null default false,
  sweepstakes_club text, official_protest boolean not null default false,
  arba_report_filed boolean not null default false
);
create table if not exists public.show_animal_coop_numbers (
  show_id uuid not null references public.shows(id) on delete cascade,
  animal_id uuid not null, section_id uuid references public.show_sections(id),
  coop_number text, scope text, breed_name text, is_manual boolean default false,
  generated_at timestamptz default now(), primary key(show_id, animal_id, section_id)
);

create table if not exists public.show_fee_settings (
  show_id uuid primary key references public.shows(id) on delete cascade,
  currency text not null default 'usd', fee_per_entry numeric not null default 0,
  fee_per_show numeric not null default 0, fur_fee numeric not null default 0,
  multi_show_discount_enabled boolean not null default false,
  multi_show_discount_type text not null default 'amount',
  multi_show_discount_value numeric not null default 0,
  multi_show_discount_basis text not null default 'each_show',
  multi_show_discount_scope text not null default 'both',
  multi_show_discount_min_entries integer not null default 0,
  multi_show_discount_max_entries integer,
  multi_show_discount_required_shows integer not null default 0
);
create table if not exists public.show_section_fee_settings (
  section_id uuid primary key references public.show_sections(id) on delete cascade,
  fee_per_entry numeric not null default 0,
  fee_per_show numeric not null default 0, fur_fee numeric not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.entry_carts (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  user_id uuid not null, status text not null default 'active',
  payment_status text not null default 'unpaid', payment_provider text,
  selected_payment_timing text, selected_payment_provider text,
  payment_amount_total numeric not null default 0, payment_currency text default 'usd',
  payment_intent_id text, checkout_session_id text, submitted_at timestamptz,
  paid_at timestamptz, created_at timestamptz default now(), updated_at timestamptz default now()
);
create table if not exists public.entry_cart_items (
  id uuid primary key default extensions.gen_random_uuid(),
  cart_id uuid not null references public.entry_carts(id) on delete cascade,
  section_id uuid not null references public.show_sections(id),
  animal_id uuid, exhibitor_id uuid references public.exhibitors(id),
  species text, tattoo text, animal_name text, breed text, variety text,
  fur_variety text, sex text, class_name text, is_fur boolean default false,
  created_at timestamptz default now()
);
create table if not exists public.show_exhibitor_balances (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_id uuid references public.exhibitors(id), exhibitor_user_id uuid,
  entry_cart_id uuid references public.entry_carts(id), cart_id uuid,
  currency text not null default 'usd', entry_count integer not null default 0,
  fur_count integer not null default 0, entries_subtotal_cents integer not null default 0,
  fur_subtotal_cents integer not null default 0, show_fee_subtotal_cents integer not null default 0,
  subtotal_before_discount_cents integer not null default 0,
  discount_cents integer not null default 0, calculated_total_cents integer not null default 0,
  paid_online_cents integer not null default 0, paid_manual_cents integer not null default 0,
  refunded_cents integer not null default 0, balance_due_cents integer not null default 0,
  payment_status text not null default 'unpaid', latest_show_payment_id uuid,
  latest_checkout_session_id text, latest_payment_intent_id text,
  section_breakdown jsonb not null default '[]', fee_snapshot jsonb not null default '{}',
  source text not null default 'cart', calculated_at timestamptz default now(),
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create unique index if not exists show_exhibitor_balances_cart_exhibitor_uidx
  on public.show_exhibitor_balances(entry_cart_id, exhibitor_id)
  where entry_cart_id is not null and exhibitor_id is not null and source='cart';

create table if not exists public.show_payment_settings (
  show_id uuid primary key references public.shows(id) on delete cascade,
  stripe_enabled boolean default false, square_enabled boolean default false,
  paypal_enabled boolean default false, default_online_provider text
);
create table if not exists public.show_payment_account_links (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  provider text not null, stripe_account_id text, provider_account_id text,
  provider_location_id text, charges_enabled boolean default false,
  account_status text, status text, created_at timestamptz default now(),
  updated_at timestamptz default now(), unique(show_id, provider)
);
create table if not exists public.payment_provider_credentials (
  id uuid primary key default extensions.gen_random_uuid(),
  payment_account_link_id uuid references public.show_payment_account_links(id) on delete cascade,
  provider text not null, access_token_ciphertext text, refresh_token_ciphertext text,
  expires_at timestamptz, granted_scopes text[] default '{}',
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create table if not exists public.show_payment_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  cart_id uuid references public.entry_carts(id), show_payment_id uuid,
  provider text not null, status text not null default 'created', currency text not null default 'usd',
  amount_cents integer not null default 0, platform_fee_cents integer not null default 0,
  metadata jsonb not null default '{}', provider_session_id text,
  provider_payment_id text,
  provider_order_id text,
  stripe_checkout_session_id text, stripe_payment_intent_id text,
  checkout_url text, expires_at timestamptz,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create unique index if not exists show_payment_sessions_stripe_checkout_uidx
  on public.show_payment_sessions(stripe_checkout_session_id);
create table if not exists public.show_payments (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_user_id uuid, exhibitor_id uuid references public.exhibitors(id),
  entry_cart_id uuid references public.entry_carts(id), cart_id uuid,
  currency text not null default 'usd', subtotal_cents integer default 0,
  total_cents integer default 0, platform_fee_cents integer default 0,
  status text not null default 'pending', payment_method text, provider text,
  payment_type text, amount_cents integer not null default 0,
  platform_fee_percent numeric, platform_fee_amount_cents integer,
  payer_user_id uuid, payment_method_type text, balance_id uuid,
  metadata jsonb not null default '{}', payment_status text,
  checkout_session_id text, stripe_checkout_session_id text,
  payment_intent_id text, stripe_payment_intent_id text, checkout_url text,
  failure_reason text, failed_at timestamptz, paid_at timestamptz, refunded_at timestamptz,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create table if not exists public.show_payment_events (
  id uuid primary key default extensions.gen_random_uuid(), provider text not null,
  event_id text not null, event_type text, payload jsonb not null default '{}',
  created_at timestamptz default now(), unique(provider,event_id)
);
create table if not exists public.show_payment_line_items (
  id uuid primary key default extensions.gen_random_uuid(),
  show_payment_id uuid, item_type text, label text, quantity integer default 1,
  unit_amount_cents integer default 0, total_amount_cents integer default 0,
  created_at timestamptz default now()
);

create or replace function public.calculate_entry_cart_balance(p_cart_id uuid)
returns setof public.show_exhibitor_balances
language plpgsql security definer set search_path='' as $$
declare
  v_show_id uuid;
  v_user_id uuid;
  v_exhibitor_id uuid;
  v_entry_count integer;
  v_fur_count integer;
  v_entries_cents integer;
  v_fur_cents integer;
  v_show_fee_cents integer;
  v_total_cents integer;
  v_breakdown jsonb;
begin
  select c.show_id,c.user_id into v_show_id,v_user_id
  from public.entry_carts c where c.id=p_cart_id;
  if v_show_id is null then raise exception 'Entry cart not found'; end if;
  if coalesce(auth.jwt()->>'role','') <> 'service_role'
     and auth.uid() is distinct from v_user_id then
    raise insufficient_privilege using message='You cannot calculate this cart';
  end if;

  for v_exhibitor_id in
    select distinct i.exhibitor_id from public.entry_cart_items i
    where i.cart_id=p_cart_id and i.exhibitor_id is not null
  loop
    select count(*)::integer,
      count(*) filter(where i.is_fur)::integer,
      coalesce(round(sum(coalesce(f.fee_per_entry,0)*100)),0)::integer,
      coalesce(round(sum(case when i.is_fur then coalesce(f.fur_fee,0)*100 else 0 end)),0)::integer
    into v_entry_count,v_fur_count,v_entries_cents,v_fur_cents
    from public.entry_cart_items i
    left join public.show_section_fee_settings f on f.section_id=i.section_id
    where i.cart_id=p_cart_id and i.exhibitor_id=v_exhibitor_id;

    select coalesce(round(sum(x.fee_per_show*100)),0)::integer
    into v_show_fee_cents
    from (
      select distinct i.section_id,coalesce(f.fee_per_show,0) fee_per_show
      from public.entry_cart_items i
      left join public.show_section_fee_settings f on f.section_id=i.section_id
      where i.cart_id=p_cart_id and i.exhibitor_id=v_exhibitor_id
    ) x;

    select coalesce(jsonb_agg(jsonb_build_object(
      'section_id',x.section_id,'entry_count',x.entry_count,
      'fur_count',x.fur_count,'entries_subtotal_cents',x.entries_cents,
      'fur_subtotal_cents',x.fur_cents,'show_fee_cents',x.show_fee_cents
    ) order by x.section_id),'[]'::jsonb)
    into v_breakdown
    from (
      select i.section_id,count(*)::integer entry_count,
        count(*) filter(where i.is_fur)::integer fur_count,
        coalesce(round(sum(coalesce(f.fee_per_entry,0)*100)),0)::integer entries_cents,
        coalesce(round(sum(case when i.is_fur then coalesce(f.fur_fee,0)*100 else 0 end)),0)::integer fur_cents,
        coalesce(round(max(coalesce(f.fee_per_show,0))*100),0)::integer show_fee_cents
      from public.entry_cart_items i
      left join public.show_section_fee_settings f on f.section_id=i.section_id
      where i.cart_id=p_cart_id and i.exhibitor_id=v_exhibitor_id
      group by i.section_id
    ) x;

    v_total_cents:=v_entries_cents+v_fur_cents+v_show_fee_cents;
    if exists(select 1 from public.show_exhibitor_balances b where b.entry_cart_id=p_cart_id and b.exhibitor_id=v_exhibitor_id) then
      update public.show_exhibitor_balances b set
        entry_count=v_entry_count,fur_count=v_fur_count,
        entries_subtotal_cents=v_entries_cents,fur_subtotal_cents=v_fur_cents,
        show_fee_subtotal_cents=v_show_fee_cents,
        subtotal_before_discount_cents=v_total_cents,
        calculated_total_cents=v_total_cents,
        balance_due_cents=greatest(0,v_total_cents-b.paid_online_cents-b.paid_manual_cents+b.refunded_cents),
        section_breakdown=v_breakdown,updated_at=now()
      where b.entry_cart_id=p_cart_id and b.exhibitor_id=v_exhibitor_id;
    else
      insert into public.show_exhibitor_balances(
        show_id,exhibitor_id,entry_cart_id,cart_id,entry_count,fur_count,
        entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,
        subtotal_before_discount_cents,calculated_total_cents,balance_due_cents,
        section_breakdown,source
      ) values(
        v_show_id,v_exhibitor_id,p_cart_id,p_cart_id,v_entry_count,v_fur_count,
        v_entries_cents,v_fur_cents,v_show_fee_cents,v_total_cents,v_total_cents,
        v_total_cents,v_breakdown,'cart'
      );
    end if;
  end loop;
  return query select b.* from public.show_exhibitor_balances b where b.entry_cart_id=p_cart_id;
end
$$;
create or replace function public.apply_show_payment_to_balance(p_payment_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_cart_id uuid;
  v_amount integer;
begin
  select coalesce(p.entry_cart_id,p.cart_id),
    greatest(coalesce(p.amount_cents,0),coalesce(p.total_cents,0))
  into v_cart_id,v_amount
  from public.show_payments p where p.id=p_payment_id;
  if v_cart_id is null then return; end if;
  update public.show_exhibitor_balances b set
    paid_online_cents=greatest(b.paid_online_cents,v_amount),
    latest_show_payment_id=p_payment_id,
    payment_status=case when v_amount>=b.calculated_total_cents then 'paid' else 'partial' end,
    balance_due_cents=greatest(0,b.calculated_total_cents-v_amount),
    updated_at=now()
  where b.entry_cart_id=v_cart_id or b.cart_id=v_cart_id;
end $$;

create table if not exists public.show_closeout_state (
  show_id uuid primary key references public.shows(id) on delete cascade,
  sync_status text default 'not_ready', is_points_stale boolean default true,
  has_warnings boolean default false, has_blocking_errors boolean default false,
  is_archived boolean default false, warning_count integer default 0,
  error_count integer default 0, blocking_error_count integer default 0,
  points_generated_at timestamptz, reports_generated_at timestamptz,
  validation_checked_at timestamptz, last_finalize_message text
);
create table if not exists public.closeout_jobs (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  status text not null default 'running',
  step text not null default 'starting',
  error text,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);
create table if not exists public.show_finalize_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  run_status text not null default 'running', started_at timestamptz default now(),
  completed_at timestamptz, results_version bigint, summary jsonb not null default '{}',
  error_summary jsonb, created_at timestamptz default now()
);
create table if not exists public.show_report_artifacts (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  finalize_run_id uuid references public.show_finalize_runs(id) on delete cascade,
  report_name public.report_type not null, artifact_status public.artifact_status not null default 'queued',
  metadata jsonb not null default '{}', is_current boolean not null default true,
  superseded_at timestamptz, storage_bucket text, storage_path text,
  file_name text, mime_type text, file_size_bytes bigint, file_hash_sha256 text,
  generated_at timestamptz, error_count integer not null default 0,
  created_at timestamptz default now(), updated_at timestamptz default now()
);
create table if not exists public.show_task_queue (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  finalize_run_id uuid references public.show_finalize_runs(id) on delete cascade,
  task_type public.show_task_type not null, task_status public.show_task_status not null default 'queued',
  report_artifact_id uuid references public.show_report_artifacts(id) on delete cascade,
  payload jsonb not null default '{}', priority integer not null default 100,
  attempt_count integer not null default 0, max_attempts integer not null default 3,
  claimed_at timestamptz, claimed_by text, completed_at timestamptz,
  failed_at timestamptz, error_message text,
  created_at timestamptz default now(), updated_at timestamptz default now()
);

create or replace function public.ensure_show_closeout_state(p_show_id uuid)
returns void language sql security definer set search_path='' as $$
  insert into public.show_closeout_state(show_id) values(p_show_id) on conflict do nothing
$$;
create or replace function public.prepare_club_delivery_targets(uuid)
returns void language plpgsql security definer set search_path='' as $$ begin return; end $$;
create or replace function public.calculate_sweepstakes_for_show(uuid,text,text)
returns void language plpgsql security definer set search_path='' as $$ begin return; end $$;
create or replace function public.sync_club_report_artifact_metadata(uuid,uuid)
returns void language plpgsql security definer set search_path='' as $$ begin return; end $$;
create or replace function public.refresh_show_reports_state(p_show_id uuid)
returns void language sql security definer set search_path='' as $$
  insert into public.show_closeout_state(show_id) values(p_show_id) on conflict do nothing
$$;
create or replace function public.show_results_readiness(uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select jsonb_build_object('ready',true)
$$;

create or replace function public.report_show_exhibitor_balances(p_show_id uuid)
returns table(
  balance_id uuid, show_id uuid, exhibitor_id uuid, exhibitor_user_id uuid,
  exhibitor_name text, showing_name text, display_name text, first_name text,
  last_name text, exhibitor_type text, phone text, email text,
  address_line1 text, address_line2 text, city text, state text, zip text,
  arba_number text, currency text, entry_count integer, fur_count integer,
  entries_subtotal_cents integer, fur_subtotal_cents integer,
  show_fee_subtotal_cents integer, subtotal_before_discount_cents integer,
  discount_cents integer, calculated_total_cents integer,
  paid_online_cents integer, paid_manual_cents integer, refunded_cents integer,
  balance_due_cents integer, payment_status text, source text, section_breakdown jsonb
)
language sql stable security definer set search_path='' as $$
  select b.id,b.show_id,b.exhibitor_id,b.exhibitor_user_id,
    coalesce(nullif(e.display_name,''),nullif(e.showing_name,''),btrim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,''))),
    e.showing_name,e.display_name,e.first_name,e.last_name,e.type,e.phone,e.email,
    e.address_line1,e.address_line2,e.city,e.state,e.zip,e.arba_number,
    b.currency,b.entry_count,b.fur_count,b.entries_subtotal_cents,b.fur_subtotal_cents,
    b.show_fee_subtotal_cents,b.subtotal_before_discount_cents,b.discount_cents,
    b.calculated_total_cents,b.paid_online_cents,b.paid_manual_cents,b.refunded_cents,
    b.balance_due_cents,b.payment_status,b.source,b.section_breakdown
  from public.show_exhibitor_balances b left join public.exhibitors e on e.id=b.exhibitor_id
  where b.show_id=p_show_id order by b.id
$$;

create table if not exists public.sweepstakes_entry_results (
  id uuid primary key default extensions.gen_random_uuid(), show_id uuid,
  section_id uuid, entry_id uuid, exhibitor_id uuid, breed text, variety text,
  points numeric default 0, award_code text, "placing" integer
);
create or replace view public.v_sweepstakes_pdf_rows with (security_invoker=true) as
  select r.id,r.show_id,r.section_id,r.entry_id,r.exhibitor_id,
    r.breed as breed_name,r.variety as variety_name,r.points,r.award_code,r."placing",
    e.species,e.sex,e.class_name,e.tattoo,e.animal_name,
    upper(sec.kind) as scope,upper(sec.letter) as show_letter,
    'LOCAL_SYNTHETIC'::text as rule_source,'VERIFIED'::text as verification_status,
    'LOCAL_SYNTHETIC'::text as engine_type,
    coalesce((select s.sanction_number from public.show_sanctions s
      where s.show_id=r.show_id and s.section_id=r.section_id
        and upper(s.sanctioning_body)='ARBA' limit 1),'') as arba_sanction_number,
    coalesce((select s.sanction_number from public.show_sanctions s
      where s.show_id=r.show_id and s.section_id=r.section_id
        and upper(s.sanctioning_body)<>'ARBA' limit 1),'') as national_club_sanction_number,
    sh.club_name as host_club_name,sh.location_name as show_location,
    sh.secretary_name,sh.secretary_email,sh.secretary_phone,
    x.display_name exhibitor_name,
    concat_ws(', ',nullif(x.address_line1,''),nullif(x.city,''),nullif(x.state,''),nullif(x.zip,'')) as exhibitor_address,
    row_number() over(partition by r.show_id,r.section_id,r.breed order by r.points desc,r.id) as rank,
    0::numeric as class_points,0::numeric as arba_class_points,
    0::numeric as variety_points,0::numeric as group_points,
    r.points as bob_points,0::numeric as bis_points,0::numeric as fur_points,
    r.points as total_points
  from public.sweepstakes_entry_results r
  left join public.entries e on e.id=r.entry_id
  left join public.exhibitors x on x.id=r.exhibitor_id
  left join public.show_sections sec on sec.id=r.section_id
  left join public.shows sh on sh.id=r.show_id;

create or replace function public.calculate_sweepstakes_for_breed(
  p_show_id uuid,
  p_breed_name text,
  p_scope text,
  p_show_letter text
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.sweepstakes_entry_results r
  where r.show_id = p_show_id
    and lower(r.breed) = lower(p_breed_name)
    and exists (
      select 1 from public.show_sections sec
      where sec.id = r.section_id
        and upper(sec.kind) = upper(p_scope)
        and upper(sec.letter) = upper(p_show_letter)
    );

  insert into public.sweepstakes_entry_results(
    show_id, section_id, entry_id, exhibitor_id, breed, variety,
    points, award_code, "placing"
  )
  select e.show_id, e.section_id, e.id, e.exhibitor_id, e.breed, e.variety,
    coalesce(sum(a.points), 0), max(a.award_code), e.placement
  from public.entries e
  join public.show_sections sec on sec.id = e.section_id
  left join public.entry_awards a on a.entry_id = e.id
  where e.show_id = p_show_id
    and lower(e.breed) = lower(p_breed_name)
    and upper(sec.kind) = upper(p_scope)
    and upper(sec.letter) = upper(p_show_letter)
    and e.is_shown and e.scratched_at is null
  group by e.show_id,e.section_id,e.id,e.exhibitor_id,e.breed,e.variety,e.placement;
end $$;

create or replace function public.report_results_entry_rows_for_breed_detail(
  p_show_id uuid,
  p_breed_name text,
  p_scope text,
  p_show_letter text
)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select row
  from public.report_results_entry_rows(p_show_id, null, p_show_letter) row
  where lower(row ->> 'breed_name') = lower(p_breed_name)
    and upper(row ->> 'section_kind') = upper(p_scope)
$$;

create or replace function public.report_results_awards_for_breed_detail(
  p_show_id uuid,
  p_breed_name text,
  p_scope text,
  p_show_letter text
)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'entry_id', e.id, 'award_code', a.award_code, 'award', a.award,
    'points', a.points, 'species', e.species,
    'breed_name', e.breed, 'variety_name', e.variety,
    'group_name', e.group_name, 'class_name', e.class_name,
    'sex', e.sex, 'tattoo', e.tattoo,
    'exhibitor_id', e.exhibitor_id,
    'exhibitor_name', coalesce(ex.display_name, btrim(coalesce(ex.first_name, '') || ' ' || coalesce(ex.last_name, ''))),
    'section_id', e.section_id, 'show_letter', upper(sec.letter),
    'section_kind', upper(sec.kind)
  )
  from public.entry_awards a
  join public.entries e on e.id = a.entry_id
  join public.show_sections sec on sec.id = e.section_id
  left join public.exhibitors ex on ex.id = e.exhibitor_id
  where e.show_id = p_show_id
    and lower(e.breed) = lower(p_breed_name)
    and upper(sec.kind) = upper(p_scope)
    and upper(sec.letter) = upper(p_show_letter)
$$;

create or replace function public.report_top_10_breeds(
  p_show_id uuid,
  p_scope text,
  p_show_letter text
)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'breed_name', e.breed,
    'entry_count', count(*),
    'exhibitor_count', count(distinct e.exhibitor_id)
  )
  from public.entries e join public.show_sections sec on sec.id=e.section_id
  where e.show_id=p_show_id and upper(sec.kind)=upper(p_scope)
    and upper(sec.letter)=upper(p_show_letter)
    and e.is_shown and e.scratched_at is null
  group by e.breed order by count(*) desc,e.breed limit 10
$$;

create or replace function public.report_payback_rows(
  p_show_id uuid,
  p_section_id uuid
)
returns setof jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'section_id', e.section_id,
    'section_label', coalesce(sec.display_name, initcap(sec.kind)||' '||upper(sec.letter)),
    'section_kind', upper(sec.kind), 'show_letter', upper(sec.letter),
    'source_type', 'class_placement', 'award_code', a.award_code,
    'award_label', coalesce(a.award, a.award_code),
    'entry_id', e.id, 'animal_id', e.animal_id,
    'breed_name', e.breed, 'variety_name', e.variety,
    'group_name', e.group_name, 'class_name', e.class_name,
    'sex', e.sex, 'tattoo', e.tattoo, 'placement', e.placement,
    'placement_label', e.placement::text, 'eligible_count', 0,
    'amount_cents', 0, 'payback_note', 'Synthetic fixture has no configured payback',
    'exhibitor_id', e.exhibitor_id, 'exhibitor_number', ex.exhibitor_number,
    'exhibitor_name', coalesce(ex.display_name, btrim(coalesce(ex.first_name, '')||' '||coalesce(ex.last_name,''))),
    'address_line1', ex.address_line1, 'address_line2', ex.address_line2,
    'city', ex.city, 'state', ex.state, 'zip', ex.zip
  )
  from public.entries e
  join public.show_sections sec on sec.id=e.section_id
  left join public.entry_awards a on a.entry_id=e.id
  left join public.exhibitors ex on ex.id=e.exhibitor_id
  where e.show_id=p_show_id and e.section_id=p_section_id
$$;

create table if not exists public.show_payback_settings (
  show_id uuid primary key, enabled boolean default false, settings jsonb default '{}'
);
create table if not exists public.show_ribbon_payout_settings (
  show_id uuid primary key, enabled boolean default false, settings jsonb default '{}'
);

alter table public.shows enable row level security;
alter table public.show_sections enable row level security;
alter table public.entries enable row level security;
alter table public.exhibitors enable row level security;
alter table public.show_report_artifacts enable row level security;
alter table public.show_finalize_runs enable row level security;
alter table public.show_task_queue enable row level security;
alter table public.show_exhibitor_balances enable row level security;

-- New local/staging databases must not accidentally expose a foundational
-- table merely because its production policy was created outside Git.
do $$
declare
  v_table record;
begin
  for v_table in
    select c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  loop
    execute format('alter table public.%I enable row level security', v_table.relname);
  end loop;
end $$;

create policy "managers read own grants" on public.show_managers for select to authenticated
  using (user_id = auth.uid());

create policy "managers read shows" on public.shows for select to authenticated
  using (public.user_can_manage_entries(id) or public.user_can_manage_show_settings(id));
create policy "managers read sections" on public.show_sections for select to authenticated
  using (public.user_can_manage_entries(show_id) or public.user_can_manage_show_settings(show_id));
create policy "managers read entries" on public.entries for select to authenticated
  using (public.user_can_manage_entries(show_id));
create policy "managers read artifacts" on public.show_report_artifacts for select to authenticated
  using (public.user_can_finalize_show(show_id,auth.uid()));
create policy "managers read finalize runs" on public.show_finalize_runs for select to authenticated
  using (public.user_can_finalize_show(show_id,auth.uid()));
create policy "managers read closeout state" on public.show_closeout_state for select to authenticated
  using (public.user_can_finalize_show(show_id,auth.uid()));
create policy "managers read render tasks" on public.show_task_queue for select to authenticated
  using (public.user_can_finalize_show(show_id,auth.uid()));
create policy "managers read balances" on public.show_exhibitor_balances for select to authenticated
  using (public.user_can_manage_entries(show_id));

grant usage on schema public to authenticated, service_role;
grant select on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;

do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
    values('show-files','show-files',false,52428800,array['application/pdf'])
    on conflict(id) do update set public=false;
  end if;
end $$;
