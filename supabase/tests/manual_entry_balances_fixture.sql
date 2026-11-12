-- Isolated regression fixture; no production data.
create schema extensions; create extension pgtap with schema extensions; create schema entry_discount_private; create schema exhibitor_fees_private; create schema auth;
create table public.shows (id uuid,name text,start_date date,end_date date,location_name text,location_address text,secretary_name text,secretary_email text,secretary_phone text,secretary_address text,club_name text,club_id uuid,coop_numbering_mode text,created_by uuid,owner_user_id uuid,is_published boolean,is_national_show boolean,national_show_section_id uuid,is_test boolean,is_locked boolean,entry_close_at timestamp with time zone,results_version bigint,results_last_changed_at timestamp with time zone,payment_timing_mode text,online_payment_fee_mode text,online_payment_fee_label text,online_payment_fee_description text,platform_fee_percent numeric,created_at timestamp with time zone,updated_at timestamp with time zone,final_award_mode text,auto_email_checkin_sheets boolean,email_sending_disabled boolean,finalized_at timestamp with time zone,is_closed boolean,is_demo boolean,demo_resets_at timestamp with time zone,timezone text,entry_open_at timestamp with time zone,locked_at timestamp with time zone,contests_enabled boolean,extras_enabled boolean);
create table public.show_sections (id uuid,show_id uuid,kind text,letter text,display_name text,judging_date date,breed_scope text,allowed_breed_ids text[],is_enabled boolean,sort_order integer);
create table public.exhibitors (id uuid,owner_user_id uuid,exhibitor_user_id uuid,created_for_show_id uuid,is_local_only boolean,is_test boolean,exhibitor_number text,showing_name text,display_name text,first_name text,last_name text,email text,phone text,type text,address_line1 text,address_line2 text,city text,state text,zip text,arba_number text,created_at timestamp with time zone,is_active boolean,is_merged boolean,merged_into_exhibitor_id uuid,merged_at timestamp with time zone,updated_at timestamp with time zone,birth_date date,claimed_by_user_id uuid,account_hidden_at timestamp with time zone,group_members jsonb,group_shows_as_youth boolean,claimed_at timestamp with time zone,imported_from text,imported_source_id uuid,imported_at timestamp with time zone);
create table public.entries (id uuid,show_id uuid,section_id uuid,exhibitor_id uuid,exhibitor_user_id uuid,animal_id uuid,species text,tattoo text,animal_name text,breed text,variety text,group_name text,fur_variety text,sex text,class_name text,status text,is_shown boolean,is_fur boolean,is_test boolean,is_disqualified boolean,scratched_at timestamp with time zone,no_show boolean,coop_number text,fur_placement integer,payment_status text,paid_at timestamp with time zone,judged_by_show_judge_id uuid,placement text,result_status text,disqualified_reason text,notes text,created_at timestamp with time zone,updated_at timestamp with time zone,special_awards text,breed_id uuid,variety_id uuid,result_entered_at timestamp with time zone,source_cart_id uuid,source_cart_item_id uuid,payment_session_id uuid,cart_entry_kind text,result_entered_by_user_id uuid,result_entered_by_name text,result_entered_by_phone text);
create table public.show_fee_settings (show_id uuid,currency text,fee_per_entry numeric,fee_per_show numeric,fur_fee numeric,multi_show_discount_enabled boolean,multi_show_discount_type text,multi_show_discount_value numeric,multi_show_discount_basis text,multi_show_discount_scope text,multi_show_discount_min_entries integer,multi_show_discount_max_entries integer,multi_show_discount_required_shows integer,canada_special_discount_enabled boolean,canada_special_discount_type text,canada_special_discount_value numeric,canada_special_discount_scope text,canada_special_show_letters text[],exhibitor_fee_enabled boolean,exhibitor_fee_label text,exhibitor_fee_amount numeric);
create table public.show_section_fee_settings (section_id uuid,fee_per_entry numeric,fee_per_show numeric,fur_fee numeric,updated_at timestamp with time zone);
create table public.entry_carts (id uuid,show_id uuid,user_id uuid,status text,payment_status text,payment_provider text,selected_payment_timing text,selected_payment_provider text,payment_amount_total numeric,payment_currency text,payment_intent_id text,checkout_session_id text,submitted_at timestamp with time zone,paid_at timestamp with time zone,created_at timestamp with time zone,updated_at timestamp with time zone,active_payment_session_id uuid,completed_payment_session_id uuid,provider_payment_id text,payment_finalized_at timestamp with time zone,payment_attempt_started_at timestamp with time zone,show_payment_id uuid,subtotal_cents integer,total_cents integer,currency text);
create table public.show_exhibitor_balances (id uuid,show_id uuid,exhibitor_id uuid,exhibitor_user_id uuid,entry_cart_id uuid,cart_id uuid,currency text,entry_count integer,fur_count integer,entries_subtotal_cents integer,fur_subtotal_cents integer,show_fee_subtotal_cents integer,subtotal_before_discount_cents integer,discount_cents integer,calculated_total_cents integer,paid_online_cents integer,paid_manual_cents integer,refunded_cents integer,balance_due_cents integer,payment_status text,latest_show_payment_id uuid,latest_checkout_session_id text,latest_payment_intent_id text,section_breakdown jsonb,fee_snapshot jsonb,source text,calculated_at timestamp with time zone,created_at timestamp with time zone,updated_at timestamp with time zone,addons_subtotal_cents integer);
create table public.show_payments (id uuid,show_id uuid,exhibitor_user_id uuid,exhibitor_id uuid,entry_cart_id uuid,cart_id uuid,currency text,subtotal_cents integer,total_cents integer,platform_fee_cents integer,status text,payment_method text,provider text,payment_type text,amount_cents integer,platform_fee_percent numeric,platform_fee_amount_cents integer,payer_user_id uuid,payment_method_type text,balance_id uuid,metadata jsonb,payment_status text,checkout_session_id text,stripe_checkout_session_id text,payment_intent_id text,stripe_payment_intent_id text,checkout_url text,failure_reason text,failed_at timestamp with time zone,paid_at timestamp with time zone,refunded_at timestamp with time zone,created_at timestamp with time zone,updated_at timestamp with time zone,stripe_account_id text,stripe_connected_account_id text,destination_account_id text,payment_session_id uuid,provider_payment_id text,provider_refund_id text,gross_charged_cents integer,online_fee_cents integer,refunded_cents integer,application_fee_refunded_cents integer);
alter table public.show_exhibitor_balances add primary key(id);
alter table public.show_exhibitor_balances alter column created_at set default now();
create unique index manual_balance_unique on public.show_exhibitor_balances(show_id,exhibitor_id) where source='entries';
create table exhibitor_fees_private.charges(cart_id uuid,exhibitor_id uuid);
create table entry_discount_private.codes(id uuid,discount_type text,value numeric,basis text,enabled boolean);
create table entry_discount_private.accepted_codes(code_id uuid,show_id uuid,exhibitor_id uuid);
create function public.is_canadian_exhibitor_address(text,text) returns boolean language sql as $$select false$$;
create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}')$$;
create function public.user_can_manage_entries(uuid) returns boolean language sql as $$select auth.jwt()->>'sub'='00000000-0000-4000-8000-000000000001'$$;
create function public.user_can_manage_show_settings(uuid) returns boolean language sql as $$select public.user_can_manage_entries($1)$$;
create function entry_discount_private.candidate(p_sections jsonb,p_type text,p_value numeric,
 p_basis text default 'per_entry',p_scope text default 'both',p_min integer default 0,
 p_required integer default 0,p_max integer default null,p_letters text[] default '{}')
returns integer language sql immutable set search_path='' as $$
 with items as (
  select s.ordinality as seq,n.i,(s.v->>'section_id') as section,
   (s.v->>'entries_subtotal_cents')::numeric/nullif((s.v->>'entry_count')::integer,0) as fee
  from jsonb_array_elements(p_sections) with ordinality s(v,ordinality)
  cross join lateral generate_series(1,coalesce((s.v->>'entry_count')::integer,0)) n(i)
  where (p_scope='both' or lower(s.v->>'kind')=p_scope)
   and (cardinality(p_letters)=0 or upper(btrim(s.v->>'letter'))=any(p_letters))
 ), ranked as (
  select *,count(*) over(partition by section) as section_count,
   row_number() over(order by seq,i) as total_rank,
   row_number() over(partition by section order by seq,i) as section_rank from items
 ), stats as (
  select count(*) as entries,count(distinct section) as sections,
   count(distinct section) filter(where section_count>=p_min) as qualifying from ranked
 ), eligible as (
  select r.* from ranked r cross join stats s
  where p_basis in ('per_entry','overall') or (p_min>0 and p_required>0 and (
   (p_basis='cumulative' and s.entries>=p_min and s.sections>=p_required and (p_max is null or total_rank<=p_max)) or
   (p_basis='each_show' and s.qualifying>=p_required and section_count>=p_min and (p_max is null or section_rank<=p_max))))
 )
 select greatest(0,round(case when p_basis='overall' and p_type='amount'
  then least(coalesce(sum(fee),0),p_value*100)
  else coalesce(sum(least(fee,greatest(0,case p_type when 'amount' then p_value*100
   when 'fixed_rate' then fee-p_value*100 when 'percent' then fee*p_value/100 else 0 end))),0) end))::integer from eligible;
$$;
revoke all on function entry_discount_private.candidate(jsonb,text,numeric,text,text,integer,integer,integer,text[]) from public,anon,authenticated;


create schema report_generation_private;
create table public.show_checkin_fee_carts(cart_id uuid,exhibitor_id uuid,carrier_base_cents integer,carrier_item_id uuid);
create table public.entry_cart_items(id uuid,section_id uuid);
create table public.show_checkin_fee_charges(cart_id uuid,exhibitor_id uuid,section_id uuid,voided_at timestamptz,amount_cents integer);
create function report_generation_private.balance_with_checkin_sections(p_balance jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_cart uuid := coalesce(p_balance ->> 'entry_cart_id', p_balance ->> 'cart_id')::uuid;
  v_base integer;
  v_carrier_section uuid;
  v_sections jsonb;
  v_fee_total integer;
  v_expected integer;
begin
  if p_balance ->> 'source' <> 'cart' then return p_balance; end if;
  select fc.carrier_base_cents, i.section_id into v_base, v_carrier_section
  from public.show_checkin_fee_carts fc join public.entry_cart_items i on i.id = fc.carrier_item_id
  where fc.cart_id = v_cart and fc.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid;
  if not found then return p_balance; end if;
  if exists (select 1 from public.show_checkin_fee_charges c where c.cart_id = v_cart
      and c.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid and c.voided_at is null and c.section_id is null) then
    raise exception 'A historical check-in fee has no section; assign its section before reporting.';
  end if;
  select coalesce(sum(c.amount_cents), 0)::integer into v_fee_total
  from public.show_checkin_fee_charges c where c.cart_id = v_cart
    and c.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid and c.voided_at is null;

  with parts as (
    select (i ->> 'section_id')::uuid section_id,
      coalesce((i ->> 'entry_count')::integer,0) - case when (i ->> 'section_id')::uuid = v_carrier_section then 1 else 0 end entry_count,
      coalesce((i ->> 'fur_count')::integer,0) fur_count,
      coalesce((i ->> 'entries_subtotal_cents')::integer,0) - case when (i ->> 'section_id')::uuid = v_carrier_section then v_base else 0 end entries_cents,
      coalesce((i ->> 'fur_subtotal_cents')::integer,0) fur_cents,
      coalesce((i ->> 'show_fee_cents')::integer,0) show_cents
    from jsonb_array_elements(coalesce(p_balance -> 'section_breakdown','[]'::jsonb)) i
    union all
    select c.section_id,0,0,0,0,c.amount_cents from public.show_checkin_fee_charges c
    where c.cart_id = v_cart and c.exhibitor_id = (p_balance ->> 'exhibitor_id')::uuid and c.voided_at is null
  ), totals as (
    select section_id,sum(entry_count) entry_count,sum(fur_count) fur_count,
      sum(entries_cents) entries_cents,sum(fur_cents) fur_cents,sum(show_cents) show_cents
    from parts group by section_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'section_id',s.id,'kind',s.kind,'letter',s.letter,'label',s.display_name,
    'entry_count',t.entry_count,'fur_count',t.fur_count,
    'entries_subtotal_cents',t.entries_cents,'fur_subtotal_cents',t.fur_cents,'show_fee_cents',t.show_cents
  ) order by s.id),'[]'::jsonb), coalesce(sum(t.entries_cents+t.fur_cents+t.show_cents),0)::integer
  into v_sections,v_expected
  from totals t join public.show_sections s on s.id = t.section_id
  where t.entry_count <> 0 or t.fur_count <> 0 or t.entries_cents <> 0 or t.fur_cents <> 0 or t.show_cents <> 0;
  if v_expected <> (p_balance ->> 'subtotal_before_discount_cents')::integer then
    raise exception 'Check-in fee section totals do not reconcile to the stored balance.';
  end if;
  return p_balance || jsonb_build_object(
    'section_breakdown',v_sections,
    'entry_count',(p_balance ->> 'entry_count')::integer - 1,
    'entries_subtotal_cents',(p_balance ->> 'entries_subtotal_cents')::integer - v_base,
    'show_fee_subtotal_cents',v_expected - ((p_balance ->> 'entries_subtotal_cents')::integer - v_base) - coalesce((p_balance ->> 'fur_subtotal_cents')::integer,0)
  );
end;
$$;
revoke all on function report_generation_private.balance_with_checkin_sections(jsonb) from public, anon, authenticated;

