-- Preserve receipts and frozen checkout prices when an entry is reassigned.
-- These are financial projections: the original payment and quote never move.
create schema if not exists show_finances_private;
revoke all on schema show_finances_private from public, anon, authenticated;

create table show_finances_private.events (
 id uuid primary key default gen_random_uuid(),
 show_id uuid not null references public.shows(id) on delete cascade,
 exhibitor_id uuid not null references public.exhibitors(id),
 actor_user_id uuid, kind text not null check(kind in ('payment','credit','allocation')),
 amount_cents integer not null default 0 check(amount_cents>=0),
 reason text, payment_id uuid references public.show_payments(id),
 request_id uuid unique, details jsonb not null default '{}', created_at timestamptz not null default now()
);
create index on show_finances_private.events(show_id,exhibitor_id,created_at);
create index on show_finances_private.events(payment_id);
alter table show_finances_private.events enable row level security;
revoke all on show_finances_private.events from public,anon,authenticated;
create table show_finances_private.legacy_receipts (
 show_id uuid not null references public.shows(id) on delete cascade,
 exhibitor_id uuid not null references public.exhibitors(id),
 online_cents integer not null, manual_cents integer not null, refunded_cents integer not null,
 primary key(show_id,exhibitor_id)
);
alter table show_finances_private.legacy_receipts enable row level security;
revoke all on show_finances_private.legacy_receipts from public,anon,authenticated;

-- Cumulative rounding conserves every cent, including partial receipts/refunds.
create function show_finances_private.share(p_total integer,p_before bigint,p_weight bigint,p_all bigint)
returns integer language sql immutable set search_path='' as $$
 select case when p_all>0 then (floor(p_total::numeric*(p_before+p_weight)/p_all)-floor(p_total::numeric*p_before/p_all))::integer else 0 end;
$$;

create function show_finances_private.cart_parts(p_balance jsonb)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_cart uuid:=coalesce(p_balance->>'entry_cart_id',p_balance->>'cart_id')::uuid;
 v_original uuid:=(p_balance->>'exhibitor_id')::uuid;
 v_items jsonb; v_atoms jsonb; v_sections jsonb; v_total bigint; v_class bigint;
 v_discount integer:=coalesce((p_balance->>'discount_cents')::integer,0);
 v_valid boolean; r record; v_row jsonb;
begin
 -- Most checkouts need no projection; avoid changing legacy pricing/receipts.
 if not exists(select 1 from public.entries e join public.entry_cart_items i on i.id=e.source_cart_item_id
   where e.source_cart_id=v_cart and i.exhibitor_id=v_original
    and (e.exhibitor_id is distinct from i.exhibitor_id or e.section_id is distinct from i.section_id)) then
  return next report_generation_private.balance_with_checkin_sections(p_balance); return;
 end if;
 select s.quote_snapshot->'cart_items' into v_items from public.show_payment_sessions s
 where s.cart_id=v_cart and s.status in ('paid','partially_refunded','refunded')
  and jsonb_typeof(s.quote_snapshot->'cart_items')='array'
  and not coalesce((s.quote_snapshot->>'settles_submitted_entries')::boolean,false)
 order by s.created_at,s.id limit 1;
 -- Submitted pay-at-show carts have frozen items, but no online session.
 if v_items is null then
  select jsonb_agg(to_jsonb(i)) into v_items from public.entry_cart_items i
  join public.entry_carts c on c.id=i.cart_id where i.cart_id=v_cart and c.status='submitted';
 end if;
 if v_items is null then raise exception 'The original checkout details are missing. Review this payment allocation before moving entries.'; end if;

 -- Never estimate from today's fee settings. A missing/ambiguous frozen line
 -- fails closed, so reassignment cannot silently create or lose a payment.
 v_sections:=p_balance->'section_breakdown';
 with items as (select i from jsonb_array_elements(v_items) i where i->>'exhibitor_id'=v_original::text
  and not coalesce((i->>'is_show_addon_carrier')::boolean,false)
  and not coalesce((i->>'is_checkin_fee_carrier')::boolean,false)
  and not coalesce((i->>'is_exhibitor_fee_carrier')::boolean,false))
 select coalesce(bool_and(
  coalesce((s->>'entry_count')::integer,0)=(select count(*) from items where i->>'section_id'=s->>'section_id' and not coalesce((i->>'is_fur')::boolean,false))
  and coalesce((s->>'fur_count')::integer,0)=(select count(*) from items where i->>'section_id'=s->>'section_id' and coalesce((i->>'is_fur')::boolean,false))),false)
 into v_valid from jsonb_array_elements(coalesce(v_sections,'[]')) s;
 if exists(select 1 from jsonb_array_elements(v_items) i
  where i->>'exhibitor_id'=v_original::text
   and not coalesce((i->>'is_show_addon_carrier')::boolean,false)
   and not coalesce((i->>'is_checkin_fee_carrier')::boolean,false)
   and not coalesce((i->>'is_exhibitor_fee_carrier')::boolean,false)
   and not exists(select 1 from jsonb_array_elements(coalesce(v_sections,'[]')) s where s->>'section_id'=i->>'section_id'))
  or exists(select 1 from public.entries e where e.source_cart_id=v_cart and e.source_cart_item_id is not null
   group by e.source_cart_item_id,coalesce(e.is_fur,false) having count(*)>1) then v_valid:=false; end if;
 if not v_valid then raise exception 'The frozen checkout counts need financial review before entries can be reassigned.'; end if;

 with items as (
  select i,coalesce((i->>'is_fur')::boolean,false) fur,
   coalesce(e.exhibitor_id,v_original) recipient,coalesce(e.section_id,(i->>'section_id')::uuid) section_id,
   row_number() over(partition by i->>'section_id',coalesce((i->>'is_fur')::boolean,false) order by i->>'id') rn,
   count(*) over(partition by i->>'section_id',coalesce((i->>'is_fur')::boolean,false)) cnt
  from jsonb_array_elements(v_items) i
  left join public.entries e on e.source_cart_id=v_cart and e.source_cart_item_id=(i->>'id')::uuid
   and coalesce(e.is_fur,false)=coalesce((i->>'is_fur')::boolean,false)
  where i->>'exhibitor_id'=v_original::text
   and not coalesce((i->>'is_show_addon_carrier')::boolean,false)
   and not coalesce((i->>'is_checkin_fee_carrier')::boolean,false)
   and not coalesce((i->>'is_exhibitor_fee_carrier')::boolean,false)
 ), atoms as (
  select i->>'id' key,recipient,section_id,case when fur then 'fur' else 'entry' end kind,
   show_finances_private.share(coalesce((s->>case when fur then 'fur_subtotal_cents' else 'entries_subtotal_cents' end)::integer,0),rn-1,1,cnt) cents,
   not fur and coalesce((s->>'discount_scope_eligible')::boolean,true) discount_eligible
  from items join jsonb_array_elements(v_sections) s on s->>'section_id'=i->>'section_id'
  union all
  select 'fee:'||(s->>'section_id'),v_original,(s->>'section_id')::uuid,'fee',coalesce((s->>'show_fee_cents')::integer,0),false
   from jsonb_array_elements(v_sections) s
  union all
  select 'addons',v_original,null,'addon',coalesce((p_balance->>'addons_subtotal_cents')::integer,0),false
 ) select jsonb_agg(to_jsonb(a) order by key),sum(cents),sum(case when discount_eligible then cents else 0 end)
 into v_atoms,v_total,v_class from atoms a;
 if v_total is distinct from (p_balance->>'subtotal_before_discount_cents')::integer
  or v_total-v_discount is distinct from (p_balance->>'calculated_total_cents')::integer
  or v_discount>v_class then
  raise exception 'The original checkout amounts do not reconcile. Review this payment allocation before moving entries.';
 end if;
 -- Allocation is proportional to frozen, discounted charges. Deterministic
 -- cent rounding is used for partial payment/refund amounts, never duplication.
 with atoms as (
  select a.*,show_finances_private.share(v_discount,
   coalesce(sum(case when discount_eligible then cents else 0 end) over(order by key rows between unbounded preceding and 1 preceding),0)::bigint,
   case when discount_eligible then cents else 0 end,v_class) discount
  from jsonb_to_recordset(v_atoms) a(key text,recipient uuid,section_id uuid,kind text,cents integer,discount_eligible boolean)
 ), net as (
  select *,cents-discount weight,coalesce(sum(cents-discount) over(order by key rows between unbounded preceding and 1 preceding),0)::bigint before
  from atoms
 ), paid as (
  select *,show_finances_private.share(coalesce((p_balance->>'paid_online_cents')::integer,0),before,weight,v_total-v_discount) online,
   show_finances_private.share(coalesce((p_balance->>'paid_manual_cents')::integer,0),before,weight,v_total-v_discount) manual,
   show_finances_private.share(coalesce((p_balance->>'refunded_cents')::integer,0),before,weight,v_total-v_discount) refunded
  from net
 ) select jsonb_agg(to_jsonb(p)) into v_atoms from paid p;
 for r in select distinct recipient from jsonb_to_recordset(v_atoms) a(recipient uuid) union select v_original loop
  with atoms as (select * from jsonb_to_recordset(v_atoms) a(recipient uuid,section_id uuid,kind text,cents integer,discount integer,online integer,manual integer,refunded integer) where recipient=r.recipient),
  sections as (
   select section_id,count(*) filter(where kind='entry') entry_count,count(*) filter(where kind='fur') fur_count,
    coalesce(sum(cents) filter(where kind='entry'),0) entries_subtotal_cents,
    coalesce(sum(cents) filter(where kind='fur'),0) fur_subtotal_cents,
    coalesce(sum(cents) filter(where kind='fee'),0) show_fee_cents
   from atoms where section_id is not null group by section_id
  ) select jsonb_build_object('exhibitor_id',r.recipient,
   'entry_count',count(*) filter(where kind='entry'),'fur_count',count(*) filter(where kind='fur'),
   'entries_subtotal_cents',coalesce(sum(cents) filter(where kind='entry'),0),
   'fur_subtotal_cents',coalesce(sum(cents) filter(where kind='fur'),0),
   'show_fee_subtotal_cents',coalesce(sum(cents) filter(where kind='fee'),0),
   'addons_subtotal_cents',coalesce(sum(cents) filter(where kind='addon'),0),
   'subtotal_before_discount_cents',coalesce(sum(cents),0),'discount_cents',coalesce(sum(discount),0),
   'calculated_total_cents',coalesce(sum(cents-discount),0),
   'paid_online_cents',coalesce(sum(online),0)+case when v_total=v_discount and r.recipient=v_original then coalesce((p_balance->>'paid_online_cents')::integer,0) else 0 end,
   'paid_manual_cents',coalesce(sum(manual),0)+case when v_total=v_discount and r.recipient=v_original then coalesce((p_balance->>'paid_manual_cents')::integer,0) else 0 end,
   'refunded_cents',coalesce(sum(refunded),0)+case when v_total=v_discount and r.recipient=v_original then coalesce((p_balance->>'refunded_cents')::integer,0) else 0 end,
   'section_breakdown',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object('kind',ss.kind,'letter',ss.letter,'label',coalesce(ss.display_name,initcap(ss.kind::text)||' '||ss.letter))) from sections t join public.show_sections ss on ss.id=t.section_id),'[]'),
   'allocation_source_exhibitor_id',v_original,'allocation_source_balance_id',p_balance->>'id')
  into v_row from atoms;
  return next p_balance||v_row;
 end loop;
end $$;

create or replace function manual_entry_balances_private.refresh(p_show uuid, p_exhibitor uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 f public.show_fee_settings; b public.show_exhibitor_balances;
 v_cart_sections jsonb; v_manual_sections jsonb; v_sections jsonb;
 v_cart_discount integer; v_best integer:=0; v_candidate integer; v_discount integer;
 v_online integer; v_manual integer; v_refunded integer;
 v_direct_online integer; v_direct_manual integer; v_direct_refunded integer;
 v_entries integer; v_fur integer; v_entry_cents integer; v_fur_cents integer;
 v_show_cents integer; v_addons integer; v_total integer; v_due integer;
 v_credit integer; v_original_online integer; v_original_manual integer; v_original_refunded integer; v_allocations jsonb; v_write text;
 v_canadian boolean; v_id uuid; d record; v_previous text;
begin
 if p_show is null or p_exhibitor is null then return; end if;
 if current_setting('ringmaster.manual_balance_refresh',true)='on' then return; end if;
 -- This private function is callable only by trusted triggers / migration owner.
 if not exists(select 1 from public.entries where show_id=p_show and exhibitor_id=p_exhibitor and source_cart_id is null)
  and not exists(select 1 from public.show_exhibitor_balances where show_id=p_show and exhibitor_id=p_exhibitor
   and source='entries' and fee_snapshot->>'maintained_by'='manual_entry_balances')
  and not exists(select 1 from public.show_exhibitor_balances cb join public.entry_carts c on c.id=coalesce(cb.entry_cart_id,cb.cart_id)
   where cb.show_id=p_show and cb.source='cart' and c.status='submitted' and (cb.exhibitor_id=p_exhibitor or exists(select 1 from public.entries e where e.source_cart_id=c.id and e.exhibitor_id=p_exhibitor))) then return; end if;
 select * into b from public.show_exhibitor_balances
 where show_id=p_show and exhibitor_id=p_exhibitor and source='entries' for update;
 if not found then
  -- Serialize first snapshot creation. Existing balances use their row lock,
  -- matching payment writers' lock order.
  perform pg_advisory_xact_lock(hashtextextended('manual-entry-balance:'||p_show::text||':'||p_exhibitor::text,0));
  select * into b from public.show_exhibitor_balances
   where show_id=p_show and exhibitor_id=p_exhibitor and source='entries' for update;
 end if;
 v_id:=coalesce(b.id,gen_random_uuid());
 select * into f from public.show_fee_settings where show_id=p_show;

 -- Include completed entry carts and assessed fee-only carts; exclude abandoned
 -- drafts. Existence of linked entries also handles checkout's transaction order.
 with originals as (
  select cb.* from public.show_exhibitor_balances cb join public.entry_carts c on c.id=coalesce(cb.entry_cart_id,cb.cart_id)
  where cb.show_id=p_show and cb.source='cart'
   and (c.status='submitted' or exists(select 1 from public.entries e where e.source_cart_id=c.id)
    or exists(select 1 from public.show_checkin_fee_carts fc where fc.cart_id=c.id)
    or exists(select 1 from exhibitor_fees_private.charges ch where ch.cart_id=c.id))
   and (cb.exhibitor_id=p_exhibitor or exists(select 1 from public.entries e where e.source_cart_id=c.id and e.exhibitor_id=p_exhibitor))
 ), parts as (
  select part from originals cb cross join lateral show_finances_private.cart_parts(to_jsonb(cb)) part
  where part->>'exhibitor_id'=p_exhibitor::text
 ) select coalesce((select jsonb_agg(s) from parts cross join lateral jsonb_array_elements(part->'section_breakdown') s),'[]'),
  coalesce(sum((part->>'discount_cents')::integer),0),coalesce(sum((part->>'paid_online_cents')::integer),0),
  coalesce(sum((part->>'paid_manual_cents')::integer),0),coalesce(sum((part->>'refunded_cents')::integer),0),
  coalesce(sum((part->>'addons_subtotal_cents')::integer),0),
  (select coalesce(sum(paid_online_cents),0) from originals where exhibitor_id=p_exhibitor),
  (select coalesce(sum(paid_manual_cents),0) from originals where exhibitor_id=p_exhibitor),
  (select coalesce(sum(refunded_cents),0) from originals where exhibitor_id=p_exhibitor),
  coalesce(jsonb_agg(jsonb_build_object('balance_id',part->>'id','cart_id',coalesce(part->>'entry_cart_id',part->>'cart_id'),
   'original_exhibitor_id',coalesce(part->>'allocation_source_exhibitor_id',part->>'exhibitor_id'),
   'paid_online_cents',part->'paid_online_cents','paid_manual_cents',part->'paid_manual_cents','refunded_cents',part->'refunded_cents')),'[]')
 into v_cart_sections,v_cart_discount,v_online,v_manual,v_refunded,v_addons,
  v_original_online,v_original_manual,v_original_refunded,v_allocations from parts;

 with sections as (
  select ss.id section_id,ss.kind::text kind,ss.letter,
   coalesce(nullif(ss.display_name,''),initcap(ss.kind::text)||' '||ss.letter) label,ss.sort_order,
   count(*) filter(where not coalesce(e.is_fur,false))::integer entry_count,
   count(*) filter(where coalesce(e.is_fur,false))::integer fur_count,
   round(sum(case when not coalesce(e.is_fur,false) then coalesce(sf.fee_per_entry,0) else 0 end)*100)::integer entries_subtotal_cents,
   round(sum(case when coalesce(e.is_fur,false) then coalesce(sf.fur_fee,0) else 0 end)*100)::integer fur_subtotal_cents,
   greatest(0,round(max(coalesce(sf.fee_per_show,0))*100)::integer-
    coalesce((select sum(coalesce((s->>'show_fee_cents')::integer,0)-coalesce((s->>'exhibitor_fee_cents')::integer,0)) from jsonb_array_elements(v_cart_sections) s
      where s->>'section_id'=ss.id::text),0))::integer show_fee_cents
  from public.entries e join public.show_sections ss on ss.id=e.section_id and ss.show_id=e.show_id
  left join public.show_section_fee_settings sf on sf.section_id=ss.id
  where e.show_id=p_show and e.exhibitor_id=p_exhibitor and e.source_cart_id is null
   and e.scratched_at is null and not coalesce(e.is_test,false)
   and lower(coalesce(e.status,'')) not in ('deleted','cancelled','canceled','scratched')
  group by ss.id,ss.kind,ss.letter,ss.display_name,ss.sort_order
 ) select coalesce(jsonb_agg(to_jsonb(s)-'sort_order' order by sort_order,kind,letter,section_id),'[]')
 into v_manual_sections from sections s;
 v_sections:=v_cart_sections||v_manual_sections;

 -- Use the same best-discount evaluator as checkout. Previously earned cart
 -- discounts are retained; only the incremental manual entries are discounted.
 if coalesce(f.multi_show_discount_enabled,false) then
  v_best:=entry_discount_private.candidate(v_sections,f.multi_show_discount_type,
   case when f.multi_show_discount_type='percent' and f.multi_show_discount_value<=1 then f.multi_show_discount_value*100 else f.multi_show_discount_value end,
   f.multi_show_discount_basis,f.multi_show_discount_scope,f.multi_show_discount_min_entries,f.multi_show_discount_required_shows,f.multi_show_discount_max_entries);
 end if;
 select public.is_canadian_exhibitor_address(state,zip) into v_canadian from public.exhibitors where id=p_exhibitor;
 if coalesce(f.canada_special_discount_enabled,false) and v_canadian then
  v_best:=greatest(v_best,entry_discount_private.candidate(v_sections,f.canada_special_discount_type,
   case when f.canada_special_discount_type='percent' and f.canada_special_discount_value<=1 then f.canada_special_discount_value*100 else f.canada_special_discount_value end,
   'per_entry',f.canada_special_discount_scope,0,0,null,
   array(select upper(btrim(x)) from unnest(f.canada_special_show_letters) x)));
 end if;
 for d in select c.* from entry_discount_private.codes c join entry_discount_private.accepted_codes a on a.code_id=c.id
  where a.show_id=p_show and a.exhibitor_id=p_exhibitor and c.enabled loop
  v_best:=greatest(v_best,entry_discount_private.candidate(v_sections,d.discount_type,d.value,d.basis));
 end loop;
 select coalesce(sum((s->>'entries_subtotal_cents')::integer),0) into v_candidate from jsonb_array_elements(v_manual_sections) s;
 v_discount:=v_cart_discount+least(v_candidate,greatest(0,v_best-v_cart_discount));

 -- Merge repeated sections so per-section reports and counts remain exact.
 select coalesce(jsonb_agg(to_jsonb(s) order by kind,letter,section_id),'[]') into v_sections from (
  select v->>'section_id' section_id,min(v->>'kind') kind,min(v->>'letter') letter,min(v->>'label') label,
   sum(coalesce((v->>'entry_count')::integer,0))::integer entry_count,
   sum(coalesce((v->>'fur_count')::integer,0))::integer fur_count,
   sum(coalesce((v->>'entries_subtotal_cents')::integer,0))::integer entries_subtotal_cents,
   sum(coalesce((v->>'fur_subtotal_cents')::integer,0))::integer fur_subtotal_cents,
   sum(coalesce((v->>'show_fee_cents')::integer,0))::integer show_fee_cents
  from jsonb_array_elements(v_sections) v group by v->>'section_id'
 ) s;
 select coalesce(sum((s->>'entry_count')::integer),0),coalesce(sum((s->>'fur_count')::integer),0),
  coalesce(sum((s->>'entries_subtotal_cents')::integer),0),coalesce(sum((s->>'fur_subtotal_cents')::integer),0),
  coalesce(sum((s->>'show_fee_cents')::integer),0)
 into v_entries,v_fur,v_entry_cents,v_fur_cents,v_show_cents from jsonb_array_elements(v_sections) s;

 -- Cart payments are already counted above. Only add payments attached to the
 -- entries balance (or legacy unallocated payments without a cart/session).
 with canonical as (
  select distinct on (coalesce(provider_payment_id,stripe_payment_intent_id,payment_intent_id,id::text)) p.*
  from public.show_payments p
  where show_id=p_show and exhibitor_id=p_exhibitor and coalesce(payment_type,'')<>'legacy_cart_parent'
   and status in ('paid','partially_refunded','refunded')
   and (balance_id=v_id or (balance_id is null and cart_id is null and payment_session_id is null))
  order by coalesce(provider_payment_id,stripe_payment_intent_id,payment_intent_id,id::text),
   (payment_session_id is not null) desc,created_at desc
 ) select coalesce(sum(greatest(coalesce(amount_cents,0),total_cents)) filter(where
    coalesce(payment_type,'')<>'manual' and coalesce(provider,'')<>'manual' and coalesce(payment_method,'')<>'manual'),0),
  coalesce(sum(greatest(coalesce(amount_cents,0),total_cents)) filter(where
    payment_type='manual' or provider='manual' or payment_method='manual'),0),
  coalesce(sum(case when refunded_cents>0 then refunded_cents when status='refunded'
    then greatest(coalesce(amount_cents,0),total_cents) else 0 end),0)
 into v_direct_online,v_direct_manual,v_direct_refunded from canonical;
 -- A prior reviewed repair may already contain the allocated cart portions.
 -- Use that baseline when capturing legacy receipts, not the original payer's
 -- amounts, or deployment would count an earlier repair a second time.
 if jsonb_typeof(b.fee_snapshot->'payment_allocations')='array' then
  select coalesce(sum((a->>'paid_online_cents')::integer),0),
   coalesce(sum((a->>'paid_manual_cents')::integer),0),coalesce(sum((a->>'refunded_cents')::integer),0)
  into v_original_online,v_original_manual,v_original_refunded
  from jsonb_array_elements(b.fee_snapshot->'payment_allocations') a;
 end if;
 -- Capture only the pre-existing amount not backed by a receipt, once.
 -- Do not use greatest(old aggregate, projected receipt): doing so would keep
 -- the original payer's credit after it has followed a reassigned entry.
 insert into show_finances_private.legacy_receipts values(p_show,p_exhibitor,
  greatest(0,coalesce(b.paid_online_cents,0)-v_original_online-v_direct_online),
  greatest(0,coalesce(b.paid_manual_cents,0)-v_original_manual-v_direct_manual),
  greatest(0,coalesce(b.refunded_cents,0)-v_original_refunded-v_direct_refunded))
 on conflict(show_id,exhibitor_id) do update set manual_cents=
  greatest(show_finances_private.legacy_receipts.manual_cents,excluded.manual_cents);
 -- Legacy trusted writers can still add unledgered manual receipts. Online
 -- allocations/refunds are never inferred from an increasing aggregate.
 select v_online+v_direct_online+online_cents,v_manual+v_direct_manual+manual_cents,
  v_refunded+v_direct_refunded+refunded_cents into v_online,v_manual,v_refunded
 from show_finances_private.legacy_receipts where show_id=p_show and exhibitor_id=p_exhibitor;
 select coalesce(sum(amount_cents),0) into v_credit from show_finances_private.events
 where show_id=p_show and exhibitor_id=p_exhibitor and kind='credit';
 v_total:=greatest(0,v_entry_cents+v_fur_cents+v_show_cents+v_addons-v_discount-v_credit);
 v_due:=greatest(0,v_total-v_online-v_manual+v_refunded);
 v_previous:=current_setting('ringmaster.manual_balance_refresh',true);
 perform set_config('ringmaster.manual_balance_refresh','on',true);
 v_write:=current_setting('ringmaster.payment_state_write',true);
 perform set_config('ringmaster.payment_state_write','on',true);
 insert into public.show_exhibitor_balances(id,show_id,exhibitor_id,exhibitor_user_id,currency,source,
  entry_count,fur_count,entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,addons_subtotal_cents,
  subtotal_before_discount_cents,discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,
  refunded_cents,balance_due_cents,payment_status,section_breakdown,fee_snapshot,calculated_at,updated_at)
 values(v_id,p_show,p_exhibitor,(select coalesce(owner_user_id,claimed_by_user_id) from public.exhibitors where id=p_exhibitor),
  lower(coalesce(f.currency,'usd')),'entries',v_entries,v_fur,v_entry_cents,v_fur_cents,v_show_cents,v_addons,
  v_entry_cents+v_fur_cents+v_show_cents+v_addons,v_discount,v_total,v_online,v_manual,v_refunded,v_due,
  case when v_online+v_manual-v_refunded>v_total then 'overpaid' when v_due=0 then 'paid'
   when v_online+v_manual-v_refunded>0 then 'partial' else 'unpaid' end,v_sections,
  coalesce(b.fee_snapshot,'{}')||jsonb_build_object('maintained_by','manual_entry_balances','source','entries','finance_credit_cents',v_credit,'payment_allocations',v_allocations),now(),now())
 on conflict(id) do update set exhibitor_user_id=excluded.exhibitor_user_id,currency=excluded.currency,
  entry_count=excluded.entry_count,fur_count=excluded.fur_count,entries_subtotal_cents=excluded.entries_subtotal_cents,
  fur_subtotal_cents=excluded.fur_subtotal_cents,show_fee_subtotal_cents=excluded.show_fee_subtotal_cents,
  addons_subtotal_cents=excluded.addons_subtotal_cents,subtotal_before_discount_cents=excluded.subtotal_before_discount_cents,
  discount_cents=excluded.discount_cents,calculated_total_cents=excluded.calculated_total_cents,
  paid_online_cents=excluded.paid_online_cents,paid_manual_cents=excluded.paid_manual_cents,refunded_cents=excluded.refunded_cents,
  balance_due_cents=excluded.balance_due_cents,payment_status=excluded.payment_status,
  section_breakdown=excluded.section_breakdown,fee_snapshot=excluded.fee_snapshot,
  calculated_at=excluded.calculated_at,updated_at=excluded.updated_at;
 if b.id is not null and (b.paid_online_cents is distinct from v_online or b.paid_manual_cents is distinct from v_manual
   or b.refunded_cents is distinct from v_refunded or b.calculated_total_cents is distinct from v_total) then
  insert into show_finances_private.events(show_id,exhibitor_id,actor_user_id,kind,details)
  values(p_show,p_exhibitor,auth.uid(),'allocation',jsonb_build_object('previous_total_cents',b.calculated_total_cents,
   'total_cents',v_total,'previous_paid_online_cents',b.paid_online_cents,'paid_online_cents',v_online,
   'previous_paid_manual_cents',b.paid_manual_cents,'paid_manual_cents',v_manual,'payment_allocations',v_allocations));
 end if;
 perform set_config('ringmaster.payment_state_write',coalesce(v_write,'off'),true);
 perform set_config('ringmaster.manual_balance_refresh',coalesce(v_previous,'off'),true);
end $$;

create or replace function manual_entry_balances_private.cart_balance_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record;
begin
 if current_setting('ringmaster.manual_balance_refresh',true)='on' then return null; end if;
 -- Entry refunds update balances before the receipt ledger, then delete the
 -- refunded entries. Let that final entry trigger refresh the complete state.
 if tg_op='UPDATE' and current_setting('ringmaster.payment_state_write',true)='on'
  and coalesce((new.fee_snapshot->>'entry_refund_credit_cents')::integer,0)>coalesce((old.fee_snapshot->>'entry_refund_credit_cents')::integer,0) then return null; end if;
 if new.source='cart' then
  for r in select new.exhibitor_id id union select e.exhibitor_id from public.entries e
   where e.source_cart_id=coalesce(new.entry_cart_id,new.cart_id) order by id loop
   perform manual_entry_balances_private.refresh(new.show_id,r.id);
  end loop;
 elsif new.source='entries' then
  perform manual_entry_balances_private.refresh(new.show_id,new.exhibitor_id);
 end if;
 return null;
end $$;

create function show_finances_private.authorize(p_show uuid)
returns void language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(public.user_can_manage_entries(p_show),false)
  and not coalesce(public.user_can_manage_show_settings(p_show),false) then
  raise exception 'You do not have permission to manage this show''s finances.' using errcode='42501';
 end if;
end $$;

create function public.get_show_finances(p_show_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb; v_sections jsonb;
begin
 perform show_finances_private.authorize(p_show_id);
 select coalesce(jsonb_agg(id order by sort_order,id),'[]') into v_sections
  from public.show_sections where show_id=p_show_id and is_enabled;
 with selected as (
  select b.* from public.show_exhibitor_balances b left join public.entry_carts c on c.id=coalesce(b.entry_cart_id,b.cart_id)
  where b.show_id=p_show_id and (b.source='entries' or (b.source='cart' and c.status='submitted'
   and not exists(select 1 from public.show_exhibitor_balances a where a.show_id=b.show_id and a.exhibitor_id=b.exhibitor_id and a.source='entries')))
 ), totals as (
  select exhibitor_id,currency,sum(calculated_total_cents)::integer charges_cents,
   sum(paid_online_cents)::integer online_cents,sum(paid_manual_cents)::integer manual_cents,
   sum(refunded_cents)::integer refunded_cents,sum(balance_due_cents)::integer due_cents,
   sum(coalesce((fee_snapshot->>'finance_credit_cents')::integer,0))::integer credit_cents,
   sum(entry_count)::integer entry_count,sum(fur_count)::integer fur_count
  from selected group by exhibitor_id,currency
 ) select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('name',coalesce(nullif(btrim(ex.showing_name),''),nullif(btrim(ex.display_name),''),nullif(btrim(concat_ws(' ',ex.first_name,ex.last_name)),''),'Exhibitor'),
  'number',ex.exhibitor_number,'email',ex.email,'phone',ex.phone) order by lower(coalesce(ex.showing_name,ex.display_name,ex.last_name,'')),t.exhibitor_id),'[]')
 into v_rows from totals t join public.exhibitors ex on ex.id=t.exhibitor_id;
 return jsonb_build_object('show_name',(select name from public.shows where id=p_show_id),'section_ids',v_sections,'exhibitors',v_rows);
end $$;

create function public.get_show_finance_history(p_show_id uuid,p_exhibitor_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform show_finances_private.authorize(p_show_id);
 return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(e)-'request_id' order by created_at desc,id) from show_finances_private.events e
  where show_id=p_show_id and exhibitor_id=p_exhibitor_id),'[]'),
 'payments',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'original_exhibitor_id',p.exhibitor_id,
   'payer_name',coalesce(nullif(ex.showing_name,''),nullif(ex.display_name,''),concat_ws(' ',ex.first_name,ex.last_name)),
   'amount_cents',coalesce(p.amount_cents,p.total_cents,0),'refunded_cents',coalesce(p.refunded_cents,0),'currency',p.currency,
   'status',p.status,'method',coalesce(p.payment_method,p.provider),'recorded_externally',p.payment_type='manual',
   'reference',p.metadata->>'reference','paid_at',p.paid_at,'created_at',p.created_at,'balance_id',p.balance_id)
  order by p.created_at desc,p.id) from public.show_payments p left join public.exhibitors ex on ex.id=p.exhibitor_id
  where p.show_id=p_show_id and coalesce(p.payment_type,'')<>'legacy_cart_parent'
   and (p.exhibitor_id=p_exhibitor_id or p.balance_id in (
    select (a->>'balance_id')::uuid from public.show_exhibitor_balances b cross join lateral jsonb_array_elements(coalesce(b.fee_snapshot->'payment_allocations','[]')) a
    where b.show_id=p_show_id and b.exhibitor_id=p_exhibitor_id and b.source='entries'))),'[]'),
 'allocations',coalesce((select fee_snapshot->'payment_allocations' from public.show_exhibitor_balances where show_id=p_show_id and exhibitor_id=p_exhibitor_id and source='entries'),'[]'));
end $$;

create function public.record_show_finance_payment(p_show_id uuid,p_exhibitor_id uuid,p_amount_cents integer,
 p_method text,p_paid_at timestamptz,p_reference text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.show_exhibitor_balances; ev show_finances_private.events; pid uuid;
 m text:=lower(btrim(p_method)); v_payload jsonb;
begin
 perform show_finances_private.authorize(p_show_id);
 if p_request_id is null or p_amount_cents is null or p_amount_cents<=0 or m is null
  or m not in ('cash','check','paypal','venmo','zelle','digital','stripe','square','other')
  or p_paid_at is null or p_paid_at>now()+interval '5 minutes'
  or length(coalesce(p_reference,''))>500 then raise exception 'Enter a valid amount, method, receipt date and reference.' using errcode='22023'; end if;
 v_payload:=jsonb_build_object('method',m,'paid_at',p_paid_at,'reference',btrim(coalesce(p_reference,'')));
 perform pg_advisory_xact_lock(hashtextextended('finance-request:'||p_request_id::text,0));
 select * into ev from show_finances_private.events where request_id=p_request_id;
 if found then
  if ev.show_id<>p_show_id or ev.exhibitor_id<>p_exhibitor_id or ev.kind<>'payment'
   or ev.amount_cents<>p_amount_cents or ev.details<>v_payload then raise exception 'This request was already used for a different transaction.' using errcode='22023'; end if;
  return jsonb_build_object('payment_id',ev.payment_id,'amount_cents',ev.amount_cents);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('checkin-fee:'||p_show_id::text||':'||p_exhibitor_id::text,0));
 perform manual_entry_balances_private.refresh(p_show_id,p_exhibitor_id);
 select * into b from public.show_exhibitor_balances where show_id=p_show_id and exhibitor_id=p_exhibitor_id and source='entries' for update;
 if not found or b.balance_due_cents<=0 then raise exception 'This exhibitor does not have an outstanding submitted-entry balance.' using errcode='22023'; end if;
 if p_amount_cents>b.balance_due_cents then raise exception 'Payment amount cannot exceed the outstanding balance. Refresh and try again.' using errcode='22023'; end if;
 insert into public.show_payments(show_id,exhibitor_id,balance_id,currency,status,payment_status,payment_method,payment_method_type,
  payment_type,provider,amount_cents,total_cents,platform_fee_percent,platform_fee_cents,platform_fee_amount_cents,online_fee_cents,paid_at,metadata)
 values(p_show_id,p_exhibitor_id,b.id,b.currency,'paid','paid',m,m,'manual',m,p_amount_cents,p_amount_cents,0,0,0,0,p_paid_at,
  jsonb_build_object('reference',btrim(coalesce(p_reference,'')),'source','show_finances','recorded_by',auth.uid(),'receipt_preference','no_receipt')) returning id into pid;
 insert into show_finances_private.events(show_id,exhibitor_id,actor_user_id,kind,amount_cents,reason,payment_id,request_id,details)
 values(p_show_id,p_exhibitor_id,auth.uid(),'payment',p_amount_cents,btrim(coalesce(p_reference,'')),pid,p_request_id,v_payload);
 perform manual_entry_balances_private.refresh(p_show_id,p_exhibitor_id);
 return jsonb_build_object('payment_id',pid,'amount_cents',p_amount_cents);
end $$;

create function public.credit_show_finance_balance(p_show_id uuid,p_exhibitor_id uuid,p_amount_cents integer,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.show_exhibitor_balances; ev show_finances_private.events;
begin
 perform show_finances_private.authorize(p_show_id);
 if p_request_id is null or p_amount_cents is null or p_amount_cents<=0 or length(btrim(coalesce(p_reason,'')))<5 or length(p_reason)>500 then
  raise exception 'Enter a positive credit and a reason (5–500 characters).' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('finance-request:'||p_request_id::text,0));
 select * into ev from show_finances_private.events where request_id=p_request_id;
 if found then
  if ev.show_id<>p_show_id or ev.exhibitor_id<>p_exhibitor_id or ev.kind<>'credit' or ev.amount_cents<>p_amount_cents or ev.reason<>btrim(p_reason) then
   raise exception 'This request was already used for a different transaction.' using errcode='22023'; end if;
  return jsonb_build_object('credit_id',ev.id);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('checkin-fee:'||p_show_id::text||':'||p_exhibitor_id::text,0));
 perform manual_entry_balances_private.refresh(p_show_id,p_exhibitor_id);
 select * into b from public.show_exhibitor_balances where show_id=p_show_id and exhibitor_id=p_exhibitor_id and source='entries' for update;
 if not found or p_amount_cents>b.balance_due_cents then raise exception 'Credit cannot exceed the outstanding balance. Refresh and try again.' using errcode='22023'; end if;
 insert into show_finances_private.events(show_id,exhibitor_id,actor_user_id,kind,amount_cents,reason,request_id)
 values(p_show_id,p_exhibitor_id,auth.uid(),'credit',p_amount_cents,btrim(p_reason),p_request_id) returning * into ev;
 perform manual_entry_balances_private.refresh(p_show_id,p_exhibitor_id);
 return jsonb_build_object('credit_id',ev.id);
end $$;

-- Existing Check-In entry points share the same authoritative balance and writer.
create or replace function public.get_show_checkin_payment_context(p_show_id uuid,p_exhibitor_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_due integer; v_currency text;
begin
 perform show_finances_private.authorize(p_show_id);
 select coalesce(sum((x->>'due_cents')::integer),0),min(x->>'currency') into v_due,v_currency
 from jsonb_array_elements(public.get_show_finances(p_show_id)->'exhibitors') x where x->>'exhibitor_id'=p_exhibitor_id::text;
 return jsonb_build_object('balance_due_cents',v_due,'currency',coalesce(v_currency,'usd'));
end $$;
create or replace function public.record_checkin_manual_payment(p_show_id uuid,p_exhibitor_id uuid,p_amount_cents integer,p_method text,p_reference text default null,p_receipt_preference text default 'no_receipt')
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=public.record_show_finance_payment(p_show_id,p_exhibitor_id,p_amount_cents,p_method,now(),p_reference,gen_random_uuid());
 update public.show_payments set metadata=coalesce(metadata,'{}')||jsonb_build_object('receipt_preference',p_receipt_preference,'source','checkin') where id=(result->>'payment_id')::uuid;
 insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,actor_user_id,details)
 values(p_show_id,p_exhibitor_id,'manual_payment_recorded','secretary',auth.uid(),result||jsonb_build_object('method',p_method));
 return result;
end $$;

revoke all on all functions in schema show_finances_private from public,anon,authenticated;
revoke all on function public.get_show_finances(uuid),public.get_show_finance_history(uuid,uuid),
 public.record_show_finance_payment(uuid,uuid,integer,text,timestamptz,text,uuid),
 public.credit_show_finance_balance(uuid,uuid,integer,text,uuid) from public,anon;
grant execute on function public.get_show_finances(uuid),public.get_show_finance_history(uuid,uuid),
 public.record_show_finance_payment(uuid,uuid,integer,text,timestamptz,text,uuid),
 public.credit_show_finance_balance(uuid,uuid,integer,text,uuid) to authenticated,service_role;
-- No bulk repricing/backfill here: identified balances are repaired in a separate,
-- reviewed data operation. Future entry/payment writes maintain their projections.
