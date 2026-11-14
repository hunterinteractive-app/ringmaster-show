-- Add actual applied discounts from authoritative balances; credits stay separate.
-- Show-level reporting only: no receipt, balance, or entry writes.
-- The checkout quote is an estimate, not the provider's final settlement fee.
-- Group household allocations before estimating a processor's fixed charge.
create or replace function show_finances_private.summary(p_show_id uuid,p_rows jsonb)
returns jsonb language sql stable set search_path='' as $$
 with balances as (
  select currency,sum(charges_cents) charges_cents,sum(discount_cents) discount_cents,sum(online_cents) online_cents,
   sum(manual_cents) manual_cents,sum(refunded_cents) refunded_cents,sum(due_cents) due_cents
  from jsonb_to_recordset(p_rows) as r(currency text,charges_cents bigint,discount_cents bigint,online_cents bigint,
   manual_cents bigint,refunded_cents bigint,due_cents bigint) group by currency
 ), receipts as materialized (
  -- A provider charge may have one allocated row per family member. Only
  -- duplicate representations of the same exhibitor's receipt are discarded.
  select distinct on (p.exhibitor_id,coalesce(p.currency,'usd'),coalesce(p.provider,''),
   coalesce(p.stripe_account_id,p.stripe_connected_account_id,p.destination_account_id,''),
   coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id,p.id::text)) p.*
  from public.show_payments p
  where p.show_id=p_show_id and p.status in ('paid','partially_refunded','refunded')
   and coalesce(p.payment_type,'') not in ('legacy_cart_parent','manual')
   and coalesce(p.provider,'')<>'manual' and coalesce(p.payment_method,'')<>'manual'
  order by p.exhibitor_id,coalesce(p.currency,'usd'),coalesce(p.provider,''),
   coalesce(p.stripe_account_id,p.stripe_connected_account_id,p.destination_account_id,''),
   coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id,p.id::text),
   (p.payment_session_id is not null) desc,p.created_at desc,p.id
 ), payment_rows as (
  select p.*,coalesce(p.currency,'usd') report_currency,
   greatest(coalesce(p.amount_cents,0),coalesce(p.total_cents,0)) principal,
   greatest(coalesce(p.online_fee_cents,0),
    coalesce((p.metadata->>'proportional_online_payment_fee_cents')::bigint,0),
    coalesce((p.metadata->>'allocated_online_fee_cents')::bigint,0)) online_fee,
   coalesce(p.payment_session_id,case when p.metadata->>'payment_session_id' ~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then (p.metadata->>'payment_session_id')::uuid end) session_id
  from receipts p
 ), checkouts as (
  select report_currency currency,session_id,
   -- With no session, keep each provider charge together (including a family).
   case when session_id is null then concat_ws(':',provider,
    coalesce(stripe_account_id,stripe_connected_account_id,destination_account_id,''),
    coalesce(provider_payment_id,stripe_payment_intent_id,payment_intent_id,id::text)) end charge_key,
   sum(principal) principal,sum(online_fee) online_fee,
   sum(coalesce(application_fee_refunded_cents,0)) platform_refund
  from payment_rows group by report_currency,session_id,charge_key
 ), checkout_costs as (
  select c.*,
   case when q.quote_snapshot->>'processing_fee_rate' is not null
    and q.quote_snapshot->>'processing_fee_fixed_cents' is not null
    and q.quote_snapshot->>'platform_fee_cents' is not null
    and (q.quote_snapshot->>'expected_amount_cents')::bigint=c.principal+c.online_fee
    and lower(q.quote_snapshot->>'currency')=lower(c.currency)
    then ceil((c.principal+c.online_fee)*(q.quote_snapshot->>'processing_fee_rate')::numeric
     +(q.quote_snapshot->>'processing_fee_fixed_cents')::numeric)::bigint
     +greatest(0,(q.quote_snapshot->>'platform_fee_cents')::bigint-c.platform_refund)
   end fee_cost
  from checkouts c left join public.show_payment_sessions q on q.id=c.session_id
 ), fees as (
  select currency,sum(principal) principal,sum(online_fee) online_fee,
   sum(fee_cost) fee_cost,count(*) filter(where fee_cost is null) unknown_checkouts
  from checkout_costs group by currency
 ), fee_refunds as (
  -- Balance refunds contain show charges only; fee refunds are recorded separately.
  select currency,sum(online_fee_cents) refunded_online_fee
  from entry_refunds_private.requests where show_id=p_show_id and status='succeeded' group by currency
 ), currencies as (
  select currency from balances union select currency from fees union select currency from fee_refunds
 ), summary as (
  select c.currency,coalesce(b.charges_cents,0) charges_cents,
   coalesce(b.discount_cents,0) discount_cents,
   coalesce(f.online_fee,0) online_fee_cents,
   coalesce(b.refunded_cents,0)+coalesce(r.refunded_online_fee,0) refunded_cents,
   coalesce(b.due_cents,0) due_cents,
   case when coalesce(f.unknown_checkouts,0)=0
     and coalesce(f.principal,0)=coalesce(b.online_cents,0)
    then coalesce(b.online_cents,0)+coalesce(b.manual_cents,0)+coalesce(f.online_fee,0)
     -coalesce(b.refunded_cents,0)-coalesce(r.refunded_online_fee,0)-coalesce(f.fee_cost,0)
   end club_earned_cents,
   coalesce(f.fee_cost,0) estimated_payment_cost_cents
  from currencies c left join balances b using(currency) left join fees f using(currency)
   left join fee_refunds r using(currency)
 ) select coalesce(jsonb_agg(to_jsonb(s) order by s.currency),'[]') from summary s;
$$;
revoke all on function show_finances_private.summary(uuid,jsonb) from public,anon,authenticated;

create or replace function public.get_show_finances(p_show_id uuid)
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
   sum(coalesce(discount_cents,0))::integer discount_cents,
   sum(paid_online_cents)::integer online_cents,sum(paid_manual_cents)::integer manual_cents,
   sum(refunded_cents)::integer refunded_cents,sum(balance_due_cents)::integer due_cents,
   sum(coalesce((fee_snapshot->>'finance_credit_cents')::integer,0))::integer credit_cents,
   sum(entry_count)::integer entry_count,sum(fur_count)::integer fur_count
  from selected group by exhibitor_id,currency
 ) select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('name',coalesce(nullif(btrim(ex.showing_name),''),nullif(btrim(ex.display_name),''),nullif(btrim(concat_ws(' ',ex.first_name,ex.last_name)),''),'Exhibitor'),
  'first_name',ex.first_name,'last_name',ex.last_name,'number',ex.exhibitor_number,'email',ex.email,'phone',ex.phone) order by lower(coalesce(nullif(btrim(ex.last_name),''),nullif(btrim(ex.showing_name),''),nullif(btrim(ex.display_name),''),'Exhibitor')),lower(coalesce(ex.first_name,'')),t.exhibitor_id,t.currency),'[]')
 into v_rows from totals t join public.exhibitors ex on ex.id=t.exhibitor_id;
 return jsonb_build_object('show_name',(select name from public.shows where id=p_show_id),'section_ids',v_sections,'exhibitors',v_rows,'summaries',show_finances_private.summary(p_show_id,v_rows));
end $$;

revoke all on function public.get_show_finances(uuid) from public,anon;
grant execute on function public.get_show_finances(uuid) to authenticated,service_role;
