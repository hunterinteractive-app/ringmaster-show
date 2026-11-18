-- Forward-only automatic offsets for staff additions replacing paid checkout
-- entries. Receipts and checkout provenance remain immutable. This is a derived
-- credit, not a fabricated payment or a permanent waiver after an unscratch.
create table show_finances_private.replacement_policy (
 singleton boolean primary key default true check(singleton),
 enabled_at timestamptz not null default clock_timestamp()
);
insert into show_finances_private.replacement_policy(singleton) values(true);
alter table show_finances_private.replacement_policy enable row level security;
revoke all on show_finances_private.replacement_policy from public,anon,authenticated;

create function show_finances_private.replacement_offsets(
 p_show uuid,p_exhibitor uuid,p_manual_discount integer,p_manual_subtotal integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_enabled timestamptz; old_entry record; new_entry record;
 v_used uuid[]:='{}'; v_pairs jsonb:='[]'; v_amount integer;
begin
 select enabled_at into v_enabled from show_finances_private.replacement_policy where singleton;
 -- Only an unambiguous, fully paid, unrefunded original checkout is eligible.
 -- Reassigned or partially refunded carts continue through financial review;
 -- never guess which entry owns the remaining payment.
 for old_entry in
  select e.*, b.id balance_id,
   atom.cents-atom.discount available_cents
  from public.entries e
  join public.entry_cart_items i on i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id
   and i.exhibitor_id=e.exhibitor_id and i.section_id=e.section_id
   and coalesce(i.is_fur,false)=coalesce(e.is_fur,false)
  join public.show_exhibitor_balances b on b.source='cart' and b.show_id=e.show_id
   and b.exhibitor_id=e.exhibitor_id and coalesce(b.entry_cart_id,b.cart_id)=e.source_cart_id
  join public.entry_carts c on c.id=e.source_cart_id and c.status='submitted'
  cross join lateral jsonb_array_elements(b.section_breakdown) s
  cross join lateral (select coalesce(sum((x->>'entries_subtotal_cents')::integer)
   filter(where coalesce((x->>'discount_scope_eligible')::boolean,true)),0) cents
   from jsonb_array_elements(b.section_breakdown) x) eligible
  cross join lateral (
   -- Use the same cumulative cent allocation as payment reassignment; a
   -- discount that does not divide evenly must not lose a cent per animal.
   with items as (
    select ci.*,row_number() over(partition by ci.section_id,coalesce(ci.is_fur,false) order by ci.id) rn,
     count(*) over(partition by ci.section_id,coalesce(ci.is_fur,false)) cnt
    from public.entry_cart_items ci where ci.cart_id=e.source_cart_id and ci.exhibitor_id=p_exhibitor
     and not coalesce(ci.is_show_addon_carrier,false) and not coalesce(ci.is_checkin_fee_carrier,false)
     and not coalesce(ci.is_exhibitor_fee_carrier,false)
   ), amounts as (
    select ci.id,show_finances_private.share(
     coalesce((sb->>case when coalesce(ci.is_fur,false) then 'fur_subtotal_cents' else 'entries_subtotal_cents' end)::integer,0),
     ci.rn-1,1,ci.cnt) cents,
     not coalesce(ci.is_fur,false) and coalesce((sb->>'discount_scope_eligible')::boolean,true) eligible
    from items ci join jsonb_array_elements(b.section_breakdown) sb on sb->>'section_id'=ci.section_id::text
   ), net as (
    select id,cents,show_finances_private.share(coalesce(b.discount_cents,0),
     coalesce(sum(case when eligible then cents else 0 end) over(order by id rows between unbounded preceding and 1 preceding),0)::bigint,
     case when eligible then cents else 0 end,eligible.cents) discount
    from amounts
   ) select * from net where id=e.source_cart_item_id
  ) atom
  where e.show_id=p_show and e.exhibitor_id=p_exhibitor
   and e.scratched_at>=v_enabled and lower(coalesce(e.status,'')) not in ('deleted','cancelled','canceled')
   and not coalesce(e.is_test,false) and not coalesce(e.is_commercial,false)
   and e.species is not null and e.created_at is not null
   and s->>'section_id'=e.section_id::text
   and b.calculated_total_cents>0
   and coalesce(b.paid_online_cents,0)+coalesce(b.paid_manual_cents,0)>=b.calculated_total_cents
   and coalesce(b.refunded_cents,0)=0
   and coalesce((b.fee_snapshot->>'entry_refund_credit_cents')::integer,0)=0
   and coalesce(b.discount_cents,0)<=eligible.cents
   and not exists(select 1 from public.entries moved join public.entry_cart_items mi on mi.id=moved.source_cart_item_id
    where moved.source_cart_id=e.source_cart_id and
     (moved.exhibitor_id is distinct from mi.exhibitor_id or moved.section_id is distinct from mi.section_id))
   -- Require exact source item counts; malformed legacy checkout data fails closed.
   and (s->>case when coalesce(e.is_fur,false) then 'fur_count' else 'entry_count' end)::integer=
    (select count(*) from public.entry_cart_items ci where ci.cart_id=e.source_cart_id
     and ci.exhibitor_id=e.exhibitor_id and ci.section_id=e.section_id
     and coalesce(ci.is_fur,false)=coalesce(e.is_fur,false)
     and not coalesce(ci.is_show_addon_carrier,false) and not coalesce(ci.is_checkin_fee_carrier,false)
     and not coalesce(ci.is_exhibitor_fee_carrier,false))
   and (select count(*) from public.entries duplicate where duplicate.source_cart_item_id=e.source_cart_item_id)=1
  order by e.scratched_at,e.id
 loop
  if coalesce(old_entry.available_cents,0)<=0 then continue; end if;
  select e.id,e.tattoo,
   case when coalesce(e.is_fur,false) then round(coalesce(sf.fur_fee,0)*100)::integer
    else price.cents-show_finances_private.share(p_manual_discount,price.before,price.cents,p_manual_subtotal) end cents
  into new_entry
  from public.entries e join public.show_section_fee_settings sf on sf.section_id=e.section_id
  left join lateral (
   select * from (
    select me.id,round(coalesce(mf.fee_per_entry,0)*100)::integer cents,
     coalesce(sum(round(coalesce(mf.fee_per_entry,0)*100)) over(order by me.id rows between unbounded preceding and 1 preceding),0)::bigint before
    from public.entries me join public.show_sections ms on ms.id=me.section_id and ms.show_id=me.show_id
    left join public.show_section_fee_settings mf on mf.section_id=me.section_id
    where me.show_id=p_show and me.exhibitor_id=p_exhibitor and me.source_cart_id is null
     and me.scratched_at is null and not coalesce(me.is_test,false) and not coalesce(me.is_fur,false)
     and lower(coalesce(me.status,'')) not in ('deleted','cancelled','canceled','scratched')
   ) amounts where id=e.id
  ) price on true
  where e.show_id=p_show and e.exhibitor_id=p_exhibitor and e.section_id=old_entry.section_id
   and e.source_cart_id is null and e.source_cart_item_id is null
   and e.created_at>=v_enabled and e.created_at>old_entry.created_at
   -- Accept add-then-scratch during the same editing session as well as later additions.
   and e.created_at>=old_entry.scratched_at-interval '15 minutes'
   and e.scratched_at is null and lower(coalesce(e.status,'')) not in ('deleted','cancelled','canceled','scratched')
   and not coalesce(e.is_test,false) and not coalesce(e.is_commercial,false)
   and lower(e.species::text)=lower(old_entry.species::text)
   and coalesce(e.is_fur,false)=coalesce(old_entry.is_fur,false)
   and not(e.id=any(v_used))
  order by e.created_at,e.id limit 1;
  if not found then continue; end if;
  v_amount:=least(old_entry.available_cents,greatest(0,new_entry.cents));
  if v_amount<=0 then continue; end if;
  v_used:=array_append(v_used,new_entry.id);
  v_pairs:=v_pairs||jsonb_build_array(jsonb_build_object('scratched_entry_id',old_entry.id,
   'replacement_entry_id',new_entry.id,'section_id',old_entry.section_id,'source_balance_id',old_entry.balance_id,
   'scratched_tattoo',old_entry.tattoo,'replacement_tattoo',new_entry.tattoo,'amount_cents',v_amount));
 end loop;
 return v_pairs;
end $$;
revoke all on function show_finances_private.replacement_offsets(uuid,uuid,integer,integer) from public,anon,authenticated;

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
 v_replacements jsonb; v_replacement_credit integer; v_credit integer; v_original_online integer; v_original_manual integer; v_original_refunded integer; v_allocations jsonb; v_write text;
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
 v_replacements:=show_finances_private.replacement_offsets(p_show,p_exhibitor,v_discount-v_cart_discount,v_candidate);
 select coalesce(sum((r->>'amount_cents')::integer),0) into v_replacement_credit from jsonb_array_elements(v_replacements) r;
 v_credit:=v_credit+v_replacement_credit;
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
  coalesce(b.fee_snapshot,'{}')||jsonb_build_object('maintained_by','manual_entry_balances','source','entries','finance_credit_cents',v_credit,'replacement_credit_cents',v_replacement_credit,'replacement_offsets',v_replacements,'payment_allocations',v_allocations),now(),now())
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
   or b.refunded_cents is distinct from v_refunded or b.calculated_total_cents is distinct from v_total
   or coalesce(b.fee_snapshot->'replacement_offsets','[]') is distinct from v_replacements) then
  insert into show_finances_private.events(show_id,exhibitor_id,actor_user_id,kind,reason,details)
  values(p_show,p_exhibitor,auth.uid(),'allocation',
   case when coalesce(b.fee_snapshot->'replacement_offsets','[]') is distinct from v_replacements
    then 'Automatic scratch/replacement offset updated: '||v_replacement_credit::text||' cents. Original receipts retained.' else null end,jsonb_build_object('previous_total_cents',b.calculated_total_cents,
   'total_cents',v_total,'replacement_offsets',v_replacements,'replacement_credit_cents',v_replacement_credit,'previous_paid_online_cents',b.paid_online_cents,'paid_online_cents',v_online,
   'previous_paid_manual_cents',b.paid_manual_cents,'paid_manual_cents',v_manual,'payment_allocations',v_allocations));
 end if;
 perform set_config('ringmaster.payment_state_write',coalesce(v_write,'off'),true);
 perform set_config('ringmaster.manual_balance_refresh',coalesce(v_previous,'off'),true);
end $$;
