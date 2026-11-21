-- Private audit records for explicitly authorized unpaid checkout corrections.
-- This migration does not reprice any show or enable an end-user write API.
create table show_finances_private.cart_quote_corrections (
 balance_id uuid primary key references public.show_exhibitor_balances(id),
 show_id uuid not null,
 original_balance jsonb not null,
 original_cart jsonb not null,
 quote_items jsonb not null check(jsonb_typeof(quote_items)='array'),
 reason text not null check(length(btrim(reason))>0),
 created_at timestamptz not null default clock_timestamp()
);
alter table show_finances_private.cart_quote_corrections enable row level security;
revoke all on show_finances_private.cart_quote_corrections from public,anon,authenticated;

CREATE OR REPLACE FUNCTION show_finances_private.cart_parts(p_balance jsonb)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_cart uuid:=coalesce(p_balance->>'entry_cart_id',p_balance->>'cart_id')::uuid;
 v_original uuid:=(p_balance->>'exhibitor_id')::uuid;
 v_items jsonb; v_atoms jsonb; v_sections jsonb; v_total bigint; v_class bigint;
 v_discount integer:=coalesce((p_balance->>'discount_cents')::integer,0);
 v_valid boolean; r record; v_row jsonb;
begin
 -- Only a privileged, reviewed correction can replace a frozen zero/incorrect
 -- unpaid quote. Preserve original checkout rows and use the audited replacement
 -- item snapshot for future transfers; ordinary carts keep their existing path.
 select c.quote_items into v_items
 from show_finances_private.cart_quote_corrections c
 where c.balance_id=(p_balance->>'id')::uuid;
 -- Most checkouts need no projection; avoid changing legacy pricing/receipts.
 if not exists(select 1 from public.entries e join public.entry_cart_items i on i.id=e.source_cart_item_id
   where e.source_cart_id=v_cart and i.exhibitor_id=v_original
    and (v_items is null or exists(select 1 from jsonb_array_elements(v_items) q where q->>'id'=i.id::text))
    and (e.exhibitor_id is distinct from i.exhibitor_id or e.section_id is distinct from i.section_id)) then
  return next report_generation_private.balance_with_checkin_sections(p_balance); return;
 end if;
 if v_items is null then
 select s.quote_snapshot->'cart_items' into v_items from public.show_payment_sessions s
 where s.cart_id=v_cart and s.status in ('paid','partially_refunded','refunded')
  and jsonb_typeof(s.quote_snapshot->'cart_items')='array'
  and not coalesce((s.quote_snapshot->>'settles_submitted_entries')::boolean,false)
 order by s.created_at,s.id limit 1;
 end if;
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
end $function$

