-- Manual entry saves bypass checkout. Maintain their financial read model at
-- write time; report generation remains read-only. Frozen cart quotes are read,
-- never recalculated or overwritten by this maintenance path.
create schema if not exists manual_entry_balances_private;
revoke all on schema manual_entry_balances_private from public, anon, authenticated;

create function manual_entry_balances_private.refresh(p_show uuid, p_exhibitor uuid)
returns void language plpgsql security definer set search_path='' as $$
declare
 f public.show_fee_settings; b public.show_exhibitor_balances;
 v_cart_sections jsonb; v_manual_sections jsonb; v_sections jsonb;
 v_cart_discount integer; v_best integer:=0; v_candidate integer; v_discount integer;
 v_online integer; v_manual integer; v_refunded integer;
 v_direct_online integer; v_direct_manual integer; v_direct_refunded integer;
 v_entries integer; v_fur integer; v_entry_cents integer; v_fur_cents integer;
 v_show_cents integer; v_addons integer; v_total integer; v_due integer;
 v_canadian boolean; v_id uuid; d record; v_previous text;
begin
 if p_show is null or p_exhibitor is null then return; end if;
 if current_setting('ringmaster.manual_balance_refresh',true)='on' then return; end if;
 -- This private function is callable only by trusted triggers / migration owner.
 if not exists(select 1 from public.entries where show_id=p_show and exhibitor_id=p_exhibitor and source_cart_id is null)
  and not exists(select 1 from public.show_exhibitor_balances where show_id=p_show and exhibitor_id=p_exhibitor
   and source='entries' and fee_snapshot->>'maintained_by'='manual_entry_balances') then return; end if;
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
 with carts as (
  select cb.*, report_generation_private.balance_with_checkin_sections(to_jsonb(cb))->'section_breakdown' normalized_sections from public.show_exhibitor_balances cb join public.entry_carts c on c.id=cb.entry_cart_id
  where cb.show_id=p_show and cb.exhibitor_id=p_exhibitor and cb.source='cart'
   and (c.status='submitted' or exists(select 1 from public.entries e where e.source_cart_id=c.id and e.exhibitor_id=p_exhibitor)
    or exists(select 1 from public.show_checkin_fee_carts fc where fc.cart_id=c.id and fc.exhibitor_id=p_exhibitor)
    or exists(select 1 from exhibitor_fees_private.charges ch where ch.cart_id=c.id and ch.exhibitor_id=p_exhibitor))
 )
 select coalesce((select jsonb_agg(s.v order by cb.created_at,cb.id,s.n) from carts cb
    cross join lateral jsonb_array_elements(cb.normalized_sections) with ordinality s(v,n)),'[]'),
  coalesce(sum(discount_cents),0),coalesce(sum(paid_online_cents),0),coalesce(sum(paid_manual_cents),0),
  coalesce(sum(refunded_cents),0),coalesce(sum(addons_subtotal_cents),0)
 into v_cart_sections,v_cart_discount,v_online,v_manual,v_refunded,v_addons from carts;

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
 -- Preserve pre-ledger receipts already recorded on an authoritative balance.
 -- Gross paid and refunded amounts are cumulative; scratching is not a refund.
 v_online:=greatest(coalesce(b.paid_online_cents,0),v_online+v_direct_online);
 v_manual:=greatest(coalesce(b.paid_manual_cents,0),v_manual+v_direct_manual);
 v_refunded:=greatest(coalesce(b.refunded_cents,0),v_refunded+v_direct_refunded);
 v_total:=greatest(0,v_entry_cents+v_fur_cents+v_show_cents+v_addons-v_discount);
 v_due:=greatest(0,v_total-v_online-v_manual+v_refunded);
 v_previous:=current_setting('ringmaster.manual_balance_refresh',true);
 perform set_config('ringmaster.manual_balance_refresh','on',true);
 insert into public.show_exhibitor_balances(id,show_id,exhibitor_id,exhibitor_user_id,currency,source,
  entry_count,fur_count,entries_subtotal_cents,fur_subtotal_cents,show_fee_subtotal_cents,addons_subtotal_cents,
  subtotal_before_discount_cents,discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,
  refunded_cents,balance_due_cents,payment_status,section_breakdown,fee_snapshot,calculated_at,updated_at)
 values(v_id,p_show,p_exhibitor,(select coalesce(owner_user_id,claimed_by_user_id) from public.exhibitors where id=p_exhibitor),
  lower(coalesce(f.currency,'usd')),'entries',v_entries,v_fur,v_entry_cents,v_fur_cents,v_show_cents,v_addons,
  v_entry_cents+v_fur_cents+v_show_cents+v_addons,v_discount,v_total,v_online,v_manual,v_refunded,v_due,
  case when v_online+v_manual-v_refunded>v_total then 'overpaid' when v_due=0 then 'paid'
   when v_online+v_manual-v_refunded>0 then 'partial' else 'unpaid' end,v_sections,
  coalesce(b.fee_snapshot,'{}')||jsonb_build_object('maintained_by','manual_entry_balances','source','entries'),now(),now())
 on conflict(id) do update set exhibitor_user_id=excluded.exhibitor_user_id,currency=excluded.currency,
  entry_count=excluded.entry_count,fur_count=excluded.fur_count,entries_subtotal_cents=excluded.entries_subtotal_cents,
  fur_subtotal_cents=excluded.fur_subtotal_cents,show_fee_subtotal_cents=excluded.show_fee_subtotal_cents,
  addons_subtotal_cents=excluded.addons_subtotal_cents,subtotal_before_discount_cents=excluded.subtotal_before_discount_cents,
  discount_cents=excluded.discount_cents,calculated_total_cents=excluded.calculated_total_cents,
  paid_online_cents=excluded.paid_online_cents,paid_manual_cents=excluded.paid_manual_cents,refunded_cents=excluded.refunded_cents,
  balance_due_cents=excluded.balance_due_cents,payment_status=excluded.payment_status,
  section_breakdown=excluded.section_breakdown,fee_snapshot=excluded.fee_snapshot,
  calculated_at=excluded.calculated_at,updated_at=excluded.updated_at;
 perform set_config('ringmaster.manual_balance_refresh',coalesce(v_previous,'off'),true);
end $$;
revoke all on function manual_entry_balances_private.refresh(uuid,uuid) from public,anon,authenticated;

create function manual_entry_balances_private.entries_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record;
begin
 if tg_op='INSERT' then
  for r in select distinct show_id,exhibitor_id from new_rows order by show_id,exhibitor_id loop
   perform manual_entry_balances_private.refresh(r.show_id,r.exhibitor_id);
  end loop;
 elsif tg_op='DELETE' then
  for r in select distinct show_id,exhibitor_id from old_rows order by show_id,exhibitor_id loop
   perform manual_entry_balances_private.refresh(r.show_id,r.exhibitor_id);
  end loop;
 else
  for r in select distinct show_id,exhibitor_id from (
   (select show_id,exhibitor_id,section_id,source_cart_id,is_fur,scratched_at,is_test,status from new_rows
    except all select show_id,exhibitor_id,section_id,source_cart_id,is_fur,scratched_at,is_test,status from old_rows)
   union
   (select show_id,exhibitor_id,section_id,source_cart_id,is_fur,scratched_at,is_test,status from old_rows
    except all select show_id,exhibitor_id,section_id,source_cart_id,is_fur,scratched_at,is_test,status from new_rows)
  ) changed order by show_id,exhibitor_id loop
   perform manual_entry_balances_private.refresh(r.show_id,r.exhibitor_id);
  end loop;
 end if;
 return null;
end $$;
revoke all on function manual_entry_balances_private.entries_changed() from public,anon,authenticated;
create trigger z_manual_balance_insert after insert on public.entries referencing new table as new_rows
 for each statement execute function manual_entry_balances_private.entries_changed();
create trigger z_manual_balance_update after update on public.entries referencing old table as old_rows new table as new_rows
 for each statement execute function manual_entry_balances_private.entries_changed();
create trigger z_manual_balance_delete after delete on public.entries referencing old table as old_rows
 for each statement execute function manual_entry_balances_private.entries_changed();

create function manual_entry_balances_private.cart_balance_changed()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.source in ('cart','entries') then perform manual_entry_balances_private.refresh(new.show_id,new.exhibitor_id); end if;
 return null;
end $$;
revoke all on function manual_entry_balances_private.cart_balance_changed() from public,anon,authenticated;
create trigger z_manual_balance_cart after insert or update on public.show_exhibitor_balances
 for each row when(new.source in ('cart','entries')) execute function manual_entry_balances_private.cart_balance_changed();
