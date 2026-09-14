-- Refunds are payment operations, available to this show's secretaries/owners
-- and global super administrators. No rollout allowlist or entry-manager grant.
create schema if not exists entry_refunds_private;
revoke all on schema entry_refunds_private from public, anon, authenticated;

create table entry_refunds_private.requests (
  id uuid primary key,
  show_id uuid not null references public.shows(id),
  exhibitor_id uuid not null references public.exhibitors(id),
  payment_id uuid not null references public.show_payments(id),
  actor_user_id uuid not null references auth.users(id),
  provider text not null,
  provider_payment_id text,
  provider_account_id text,
  currency text not null,
  entry_amount_cents integer not null check(entry_amount_cents > 0),
  online_fee_cents integer not null default 0 check(online_fee_cents >= 0),
  reason text not null check(length(reason) between 3 and 500),
  entry_ids uuid[] not null check(cardinality(entry_ids) between 1 and 500),
  entry_snapshots jsonb not null,
  balance_allocations jsonb not null,
  status text not null default 'prepared'
    check(status in ('prepared','pending','needs_review','succeeded','failed')),
  provider_refund_id text,
  error_message text,
  created_at timestamptz not null default now(),
  attempted_at timestamptz,
  checked_at timestamptz,
  completed_at timestamptz
);
alter table entry_refunds_private.requests enable row level security;
create index entry_refunds_show_exhibitor on entry_refunds_private.requests(show_id,exhibitor_id,created_at desc);
create index entry_refunds_pending on entry_refunds_private.requests(checked_at) where status in ('prepared','pending','needs_review');
create index entry_refunds_payment on entry_refunds_private.requests(payment_id);
create unique index entry_refunds_provider_id on entry_refunds_private.requests(provider,coalesce(provider_account_id,''),provider_refund_id) where provider_refund_id is not null;

-- Deliberately retain the IDs after removal; the archived entry snapshots are
-- the audit trail. A failed refund releases its reservations.
create table entry_refunds_private.entries (
  entry_id uuid primary key,
  request_id uuid not null references entry_refunds_private.requests(id)
);
alter table entry_refunds_private.entries enable row level security;
create index entry_refunds_entries_request on entry_refunds_private.entries(request_id);

create function entry_refunds_private.online_fee(p public.show_payments)
returns integer language sql immutable set search_path='' as $$
  select greatest(coalesce(p.online_fee_cents,0),
    coalesce((p.metadata->>'proportional_online_payment_fee_cents')::integer,0),
    coalesce((p.metadata->>'allocated_online_fee_cents')::integer,0));
$$;

-- Retain the original merchant before issuing a direct charge. Account links
-- can change later, but a refund must always use the original merchant.
create function public.save_stripe_payment_account(p_session_id uuid,p_account_id text)
returns void language plpgsql security definer set search_path='' as $$
declare s public.show_payment_sessions%rowtype;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  select * into s from public.show_payment_sessions where id=p_session_id for update;
  if not found or s.provider<>'stripe' or not exists(select 1 from public.show_payment_account_links l
    where l.show_id=s.show_id and l.provider='stripe' and l.stripe_account_id=p_account_id) then
    raise exception 'Stripe account does not match the payment attempt.'; end if;
  if s.destination_account_id is not null and s.destination_account_id<>p_account_id then
    raise exception 'The original Stripe account for this payment cannot be changed.'; end if;
  update public.show_payment_sessions set destination_account_id=p_account_id where id=s.id;
  update public.show_payments set stripe_account_id=p_account_id
    where payment_session_id=s.id and provider='stripe' and stripe_account_id is null;
end;
$$;
revoke all on function public.save_stripe_payment_account(uuid,text) from public,anon,authenticated;
grant execute on function public.save_stripe_payment_account(uuid,text) to service_role;

-- Historical signed webhook records also contain the original account. Read
-- them when needed instead of guessing from the show's current connection.
create function entry_refunds_private.original_stripe_account(p public.show_payments)
returns text language sql stable security definer set search_path='' as $$
  select coalesce(p.stripe_account_id,p.stripe_connected_account_id,p.destination_account_id,
    (select destination_account_id from public.show_payment_sessions where id=p.payment_session_id),
    (select coalesce(e.payload->>'stripe_account_id',e.payload->>'account')
      from public.show_payment_events e where e.provider='stripe'
        and (e.payment_session_id=p.payment_session_id or e.provider_payment_id=coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id))
        and coalesce(e.payload->>'stripe_account_id',e.payload->>'account') like 'acct_%'
      order by e.created_at limit 1));
$$;

create function entry_refunds_private.can_refund(p_show uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select p_user is not null and exists(select 1 from public.shows s where s.id=p_show)
    and (public.is_super_admin(p_user)
      or exists(select 1 from public.shows s where s.id=p_show and p_user in (s.created_by,s.owner_user_id))
      or exists(select 1 from public.role_assignments r where r.show_id=p_show and r.user_id=p_user and r.role::text='admin')
      or exists(select 1 from public.show_admins a where a.show_id=p_show and a.user_id=p_user)
      or exists(select 1 from public.show_role_assignments r where r.show_id=p_show and r.user_id=p_user and r.role='show_admin'));
$$;

create function public.can_refund_show_entries(p_show_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select entry_refunds_private.can_refund(p_show_id,auth.uid());
$$;
revoke all on function public.can_refund_show_entries(uuid) from public,anon;
grant execute on function public.can_refund_show_entries(uuid) to authenticated;

-- Match a refund to the original exhibitor/cart, including pre-provenance
-- entries. Manual receipts can cover several balances for one exhibitor.
create function entry_refunds_private.eligible_entries(p_payment uuid)
returns table(entry_id uuid,suggested_cents integer)
language sql stable security definer set search_path='' as $$
  select e.id,
    greatest(0,floor(case when e.is_fur then
      coalesce((sb.s->>'fur_subtotal_cents')::numeric,0)/greatest(coalesce((sb.s->>'fur_count')::integer,0),1)
    else coalesce((sb.s->>'entries_subtotal_cents')::numeric,0)/greatest(coalesce((sb.s->>'entry_count')::integer,0),1)
      * case when coalesce(b.entries_subtotal_cents,0)>0
        then greatest(b.entries_subtotal_cents-greatest(b.discount_cents-
          coalesce((b.fee_snapshot->>'entry_refund_credit_cents')::integer,0),0),0)::numeric/b.entries_subtotal_cents else 1 end
    end))::integer
  from public.show_payments p
  join public.entries e on e.show_id=p.show_id and e.exhibitor_id=p.exhibitor_id
  left join lateral (
    select x.* from public.show_exhibitor_balances x
    where x.show_id=e.show_id and x.exhibitor_id=e.exhibitor_id
      and (x.id=p.balance_id or (p.balance_id is null and
        (x.entry_cart_id=coalesce(p.cart_id,p.entry_cart_id,e.source_cart_id) or x.source='entries')))
    order by (x.id=p.balance_id) desc nulls last,x.created_at desc limit 1
  ) b on true
  left join lateral (select s from jsonb_array_elements(coalesce(b.section_breakdown,'[]')) s
    where s->>'section_id'=e.section_id::text limit 1) sb on true
  where p.id=p_payment and not exists(select 1 from entry_refunds_private.entries r where r.entry_id=e.id)
    and (p.payment_type='manual'
      or e.source_cart_id=coalesce(p.cart_id,p.entry_cart_id)
      or (e.source_cart_id is null and exists(select 1 from public.entry_cart_items i
        where i.cart_id=coalesce(p.cart_id,p.entry_cart_id) and i.exhibitor_id=e.exhibitor_id
          and i.section_id=e.section_id and i.species=e.species
          and ((i.animal_id is not null and i.animal_id=e.animal_id)
            or ((i.animal_id is null or e.animal_id is null) and upper(i.tattoo)=upper(e.tattoo)
              and lower(i.breed)=lower(e.breed)))
          and (not e.is_fur or i.is_fur))));
$$;

create function public.get_entry_refund_options(p_show_id uuid,p_exhibitor_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_payments jsonb; v_history jsonb; v_entries jsonb;
begin
  if not entry_refunds_private.can_refund(p_show_id,auth.uid()) then
    raise exception 'Only show secretaries and administrators can issue refunds.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'section',coalesce(s.display_name,s.kind||' '||s.letter),
    'tattoo',e.tattoo,'breed',e.breed,'is_fur',e.is_fur) order by s.sort_order,e.breed,e.tattoo),'[]')
    into v_entries from public.entries e left join public.show_sections s on s.id=e.section_id
    where e.show_id=p_show_id and e.exhibitor_id=p_exhibitor_id;
  select coalesce(jsonb_agg(t.item order by t.paid_at desc),'[]') into v_payments from (
    select distinct on (coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id,p.id::text),p.balance_id)
      p.paid_at,jsonb_build_object('id',p.id,'provider',p.provider,
      'manual',p.payment_type='manual','method',coalesce(p.payment_method_type,p.payment_method,p.provider),
      'paid_at',p.paid_at,'currency',upper(p.currency),
      'remaining_entry_cents',greatest(greatest(coalesce(p.amount_cents,0),p.total_cents)-coalesce(p.refunded_cents,0)-coalesce(r.pending_base,0),0),
      'remaining_online_fee_cents',greatest(entry_refunds_private.online_fee(p)-coalesce(r.fees,0),0),
      'entries',coalesce((select jsonb_agg(jsonb_build_object('id',entry_id,'suggested_cents',suggested_cents))
        from entry_refunds_private.eligible_entries(p.id)),'[]')) item
    from public.show_payments p
    left join lateral (
      select sum(entry_amount_cents) filter(where status in ('prepared','pending','needs_review')) pending_base,
        sum(online_fee_cents) filter(where status<>'failed') fees
      from entry_refunds_private.requests x where x.show_id=p.show_id and x.exhibitor_id=p.exhibitor_id
        and (x.payment_id=p.id or (x.provider_payment_id=coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id)
          and x.provider=p.provider))
    ) r on true
    where p.show_id=p_show_id and p.exhibitor_id=p_exhibitor_id
      and p.status in ('paid','partially_refunded') and p.paid_at is not null
      and (p.payment_type='manual' or (p.provider in ('stripe','square')
        and coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id) is not null))
    order by coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id,p.id::text),p.balance_id,
      (p.payment_session_id is not null) desc,p.created_at desc
  ) t;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'status',r.status,
    'amount_cents',r.entry_amount_cents+r.online_fee_cents,'currency',upper(r.currency),
    'entry_count',cardinality(r.entry_ids),'reason',r.reason,'created_at',r.created_at,
    'error',r.error_message) order by r.created_at desc),'[]') into v_history
    from entry_refunds_private.requests r where r.show_id=p_show_id and r.exhibitor_id=p_exhibitor_id;
  return jsonb_build_object('entries',v_entries,'payments',v_payments,'history',v_history,
    'enabled',coalesce((select allow_refunds from public.show_payment_settings where show_id=p_show_id),true),
    'locked',exists(select 1 from public.shows where id=p_show_id and (is_locked or finalized_at is not null)));
end;
$$;
revoke all on function public.get_entry_refund_options(uuid,uuid) from public,anon;
grant execute on function public.get_entry_refund_options(uuid,uuid) to authenticated;

create function public.get_show_entry_refunds(p_show_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if not entry_refunds_private.can_refund(p_show_id,auth.uid()) then
    raise exception 'Only show secretaries and administrators can manage refunds.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'status',r.status,
    'exhibitor_name',coalesce(e.display_name,e.first_name||' '||e.last_name),
    'amount_cents',r.entry_amount_cents+r.online_fee_cents,'currency',upper(r.currency),
    'entry_count',cardinality(r.entry_ids),'reason',r.reason,'created_at',r.created_at,
    'error',r.error_message) order by r.created_at desc),'[]') into result
  from entry_refunds_private.requests r join public.exhibitors e on e.id=r.exhibitor_id where r.show_id=p_show_id;
  return result;
end;
$$;
revoke all on function public.get_show_entry_refunds(uuid) from public,anon;
grant execute on function public.get_show_entry_refunds(uuid) to authenticated;

create function public.prepare_entry_refund(p_id uuid,p_actor uuid,p_payment uuid,p_entry_ids uuid[],
  p_entry_amount integer,p_online_fee integer,p_reason text,p_manual_returned boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.show_payments%rowtype; r entry_refunds_private.requests%rowtype;
  b public.show_exhibitor_balances%rowtype; v_alloc jsonb:='[]'; v_remaining integer;
  v_amount integer; v_reserved integer; v_fees integer; v_entries jsonb; v_account text; v_ids uuid[];
  v_method_refunded integer; v_known_refunded integer;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  select * into p from public.show_payments where id=p_payment;
  if not found or not entry_refunds_private.can_refund(p.show_id,p_actor) then
    raise exception 'Only show secretaries and administrators can issue refunds.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('entry-refund:'||p.show_id||':'||p.exhibitor_id,0));
  select array_agg(distinct i order by i) into v_ids from unnest(p_entry_ids) i;
  select * into r from entry_refunds_private.requests where id=p_id;
  if found then
    if r.actor_user_id<>p_actor or r.payment_id<>p_payment or r.entry_ids is distinct from v_ids
      or r.entry_amount_cents is distinct from p_entry_amount or r.online_fee_cents is distinct from p_online_fee
      or r.reason is distinct from btrim(p_reason) then raise exception 'Refund request ID has already been used.'; end if;
    return to_jsonb(r);
  end if;
  perform 1 from public.shows where id=p.show_id and not coalesce(is_locked,false) and finalized_at is null for update;
  if not found then raise exception 'Unlock the show before refunding and removing entries.'; end if;
  if not coalesce((select allow_refunds from public.show_payment_settings where show_id=p.show_id),true) then
    raise exception 'Refunds are disabled in Show Fees and Payments.'; end if;
  select * into p from public.show_payments where id=p_payment for update;
  if p.status not in ('paid','partially_refunded') or p.paid_at is null then raise exception 'Payment is not refundable.'; end if;
  if p_entry_amount is null or p_entry_amount<=0 or p_online_fee is null or p_online_fee<0
    or p_entry_amount::bigint+p_online_fee>2147483647 or length(btrim(p_reason)) not between 3 and 500
    or p_reason is null or coalesce(cardinality(v_ids),0) not between 1 and 500 then raise exception 'Select entries, a valid refund amount, and a reason.'; end if;
  if p.payment_type='manual' then
    if not coalesce(p_manual_returned,false) or p_online_fee<>0 then
      raise exception 'Confirm the money was returned outside RingMaster before recording a manual refund.'; end if;
  elsif p.provider not in ('stripe','square') or coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id) is null then
    raise exception 'The original online payment cannot be refunded automatically.';
  end if;
  perform 1 from public.entries where id=any(v_ids) order by id for update;
  if (select count(*) from entry_refunds_private.eligible_entries(p.id) where entry_id=any(v_ids))<>cardinality(v_ids) then
    raise exception 'An entry is no longer available or does not belong to this payment.'; end if;
  select coalesce(sum(entry_amount_cents) filter(where status in ('prepared','pending','needs_review')),0),
    coalesce(sum(online_fee_cents) filter(where status<>'failed'),0) into v_reserved,v_fees
    from entry_refunds_private.requests x where x.show_id=p.show_id and x.exhibitor_id=p.exhibitor_id
      and (x.payment_id=p.id or (x.provider=p.provider and x.provider_payment_id=coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id)));
  if p_entry_amount>greatest(coalesce(p.amount_cents,0),p.total_cents)-coalesce(p.refunded_cents,0)-v_reserved
    or p_online_fee>entry_refunds_private.online_fee(p)-v_fees then raise exception 'Refund exceeds the remaining payment amount. Refresh and try again.'; end if;
  -- Reserve the exact accounting allocations. Online fees were not part of
  -- exhibitor balances and therefore must never be subtracted from them.
  v_remaining:=p_entry_amount;
  for b in select * from public.show_exhibitor_balances x
    where x.show_id=p.show_id and x.exhibitor_id=p.exhibitor_id
      and (x.id=p.balance_id or (p.balance_id is null and
        (p.payment_type='manual' or x.entry_cart_id=coalesce(p.cart_id,p.entry_cart_id))))
    order by x.id for update
  loop
    select coalesce(sum((a->>'amount_cents')::integer),0) into v_reserved
    from entry_refunds_private.requests x cross join lateral jsonb_array_elements(x.balance_allocations) a
    where x.status in ('prepared','pending','needs_review') and a->>'balance_id'=b.id::text;
    select coalesce(sum((a->>'amount_cents')::integer) filter(where
      (x.provider='manual')=(p.payment_type='manual')),0),coalesce(sum((a->>'amount_cents')::integer),0)
      into v_method_refunded,v_known_refunded
    from entry_refunds_private.requests x cross join lateral jsonb_array_elements(x.balance_allocations) a
    where x.status='succeeded' and a->>'balance_id'=b.id::text;
    v_amount:=least(v_remaining,greatest(0,b.calculated_total_cents-v_reserved),
      greatest(0,(case when p.payment_type='manual' then b.paid_manual_cents else b.paid_online_cents end)
        -v_method_refunded-greatest(0,b.refunded_cents-v_known_refunded)-v_reserved));
    if v_amount>0 then
      v_alloc:=v_alloc||jsonb_build_array(jsonb_build_object('balance_id',b.id,'amount_cents',v_amount));
      v_remaining:=v_remaining-v_amount;
    end if;
    exit when v_remaining=0;
  end loop;
  if v_remaining<>0 then raise exception 'The recorded balance cannot cover this refund. Review the payment history first.'; end if;
  select jsonb_agg(to_jsonb(e) order by e.id) into v_entries from public.entries e where id=any(v_ids);
  v_account:=entry_refunds_private.original_stripe_account(p);
  insert into entry_refunds_private.requests(id,show_id,exhibitor_id,payment_id,actor_user_id,
    provider,provider_payment_id,provider_account_id,currency,entry_amount_cents,online_fee_cents,
    reason,entry_ids,entry_snapshots,balance_allocations)
  values(p_id,p.show_id,p.exhibitor_id,p.id,p_actor,
    case when p.payment_type='manual' then 'manual' else p.provider end,
    coalesce(p.provider_payment_id,p.stripe_payment_intent_id,p.payment_intent_id),v_account,lower(p.currency),
    p_entry_amount,p_online_fee,btrim(p_reason),v_ids,v_entries,v_alloc) returning * into r;
  insert into entry_refunds_private.entries(entry_id,request_id) select unnest(v_ids),p_id;
  return to_jsonb(r);
end;
$$;

create function entry_refunds_private.guard_entry()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from entry_refunds_private.entries x join entry_refunds_private.requests r on r.id=x.request_id
    where x.entry_id=old.id and r.status<>'failed'
      and coalesce(current_setting('ringmaster.completing_entry_refund',true),'')<>r.id::text) then
    raise exception 'This entry has a refund in progress. Check its refund status before making changes.'; end if;
  if tg_op='DELETE' then return old; end if; return new;
end;
$$;
create trigger guard_entry_refund before update or delete on public.entries for each row execute function entry_refunds_private.guard_entry();

create function entry_refunds_private.guard_show_lock()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if (new.is_locked or new.finalized_at is not null) and exists(select 1 from entry_refunds_private.requests
    where show_id=new.id and status in ('prepared','pending','needs_review')) then
    raise exception 'Resolve pending entry refunds before locking or finalizing this show.'; end if;
  return new;
end;
$$;
create trigger guard_show_entry_refunds before update of is_locked,finalized_at on public.shows
for each row execute function entry_refunds_private.guard_show_lock();

create function public.get_entry_refund_work(p_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(r)),'[]') into result from (
    select * from entry_refunds_private.requests where (p_id is not null and id=p_id)
      or (p_id is null and status in ('prepared','pending','needs_review') and
        (checked_at is null or checked_at<now()-interval '5 minutes'))
    order by checked_at nulls first,created_at limit 25) r;
  return result;
end;
$$;

create function public.mark_entry_refund_attempt(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r entry_refunds_private.requests%rowtype;
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  update entry_refunds_private.requests set attempted_at=coalesce(attempted_at,now()),checked_at=now()
    where id=p_id returning * into r;
  return to_jsonb(r);
end;
$$;

create function public.finish_entry_refund(p_id uuid,p_status text,p_provider_refund_id text default null,
  p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r entry_refunds_private.requests%rowtype; p public.show_payments%rowtype;
  a jsonb; v_amount integer; v_previous text:=current_setting('ringmaster.payment_state_write',true);
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  select * into r from entry_refunds_private.requests where id=p_id;
  if not found then raise exception 'Refund request not found.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('entry-refund:'||r.show_id||':'||r.exhibitor_id,0));
  select * into r from entry_refunds_private.requests where id=p_id for update;
  if r.status in ('succeeded','failed') then return jsonb_build_object('id',r.id,'status',r.status); end if;
  if p_status not in ('pending','needs_review','succeeded','failed') then raise exception 'Invalid refund status.'; end if;
  if r.provider_refund_id is not null and p_provider_refund_id is not null and r.provider_refund_id<>p_provider_refund_id then
    raise exception 'Refund reference does not match.'; end if;
  if p_status='succeeded' and r.provider<>'manual' and coalesce(p_provider_refund_id,r.provider_refund_id) is null then
    raise exception 'Provider refund reference required.'; end if;
  if p_status='succeeded' then
    perform 1 from public.shows where id=r.show_id for update;
    select * into p from public.show_payments where id=r.payment_id for update;
    perform set_config('ringmaster.payment_state_write','on',true);
    for a in select value from jsonb_array_elements(r.balance_allocations) loop
      v_amount:=(a->>'amount_cents')::integer;
      update public.show_exhibitor_balances set
        discount_cents=discount_cents+v_amount,
        calculated_total_cents=greatest(0,calculated_total_cents-v_amount),
        refunded_cents=refunded_cents+v_amount,
        -- Same amount credited and returned: an entry refund must not create debt.
        fee_snapshot=coalesce(fee_snapshot,'{}')||jsonb_build_object('entry_refund_credit_cents',
          coalesce((fee_snapshot->>'entry_refund_credit_cents')::integer,0)+v_amount),updated_at=now()
      where id=(a->>'balance_id')::uuid;
      if not found then raise exception 'Refund balance is missing.'; end if;
    end loop;
    update public.show_payments set refunded_cents=coalesce(refunded_cents,0)+r.entry_amount_cents,
      status=case when coalesce(refunded_cents,0)+r.entry_amount_cents>=greatest(coalesce(amount_cents,0),total_cents) then 'refunded' else 'partially_refunded' end,
      payment_status=case when coalesce(refunded_cents,0)+r.entry_amount_cents>=greatest(coalesce(amount_cents,0),total_cents) then 'refunded' else 'partially_refunded' end,
      provider_refund_id=p_provider_refund_id,refunded_at=now(),updated_at=now()
    where id=p.id or (r.provider<>'manual' and show_id=r.show_id and exhibitor_id=r.exhibitor_id
      and provider=r.provider and balance_id is not distinct from p.balance_id
      and coalesce(provider_payment_id,stripe_payment_intent_id,payment_intent_id)=r.provider_payment_id
      and status in ('paid','partially_refunded'));
    perform set_config('ringmaster.completing_entry_refund',r.id::text,true);
    delete from public.entries where id=any(r.entry_ids) and show_id=r.show_id and exhibitor_id=r.exhibitor_id;
    perform set_config('ringmaster.completing_entry_refund','',true);
    perform set_config('ringmaster.payment_state_write',coalesce(v_previous,'off'),true);
  elsif p_status='failed' then
    delete from entry_refunds_private.entries where request_id=p_id;
  end if;
  update entry_refunds_private.requests set status=p_status,
    provider_refund_id=coalesce(p_provider_refund_id,provider_refund_id),
    error_message=left(p_error,500),checked_at=now(),
    completed_at=case when p_status in ('succeeded','failed') then now() else null end where id=p_id;
  return jsonb_build_object('id',r.id,'status',p_status);
end;
$$;

-- Preserve the credited quote on subsequent refreshes for manual/legacy
-- balances as well as carts; the original entry snapshots remain in the audit.
create function entry_refunds_private.protect_refunded_balance()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if coalesce((old.fee_snapshot->>'entry_refund_credit_cents')::integer,0)>0
    and coalesce(current_setting('ringmaster.payment_state_write',true),'off')<>'on' then
    new:=old;
  end if;
  return new;
end;
$$;
create trigger zz_protect_refunded_balance before update on public.show_exhibitor_balances
for each row execute function entry_refunds_private.protect_refunded_balance();

-- Reconciliation previously treated ANY partial refund as a refund of the
-- entire payment, and removed fully refunded payments from the gross paid sum.
-- Keep gross payments and actual refunded principal as separate amounts.
create or replace function public.apply_show_payment_to_balance(p_show_payment_id uuid)
returns public.show_exhibitor_balances language plpgsql security definer set search_path='' as $$
declare p public.show_payments%rowtype; b public.show_exhibitor_balances%rowtype;
  v_online integer; v_manual integer; v_refunded integer; v_previous text;
begin
  select * into p from public.show_payments where id=p_show_payment_id;
  if not found or p.balance_id is null then raise exception 'Payment balance not found.'; end if;
  select * into b from public.show_exhibitor_balances where id=p.balance_id for update;
  if not found then raise exception 'Payment balance not found.'; end if;
  with canonical as (
    select distinct on (coalesce(provider_payment_id,stripe_payment_intent_id,payment_intent_id,id::text)) x.*
    from public.show_payments x where x.balance_id=b.id
      and status in ('paid','partially_refunded','refunded')
    order by coalesce(provider_payment_id,stripe_payment_intent_id,payment_intent_id,id::text),
      (payment_session_id is not null) desc,created_at desc
  ) select coalesce(sum(greatest(coalesce(amount_cents,0),total_cents)) filter(where
      coalesce(payment_type,'')<>'manual' and coalesce(provider,'')<>'manual' and coalesce(payment_method,'')<>'manual'),0),
    coalesce(sum(greatest(coalesce(amount_cents,0),total_cents)) filter(where
      payment_type='manual' or provider='manual' or payment_method='manual'),0),
    coalesce(sum(case when refunded_cents>0 then refunded_cents when status='refunded'
      then greatest(coalesce(amount_cents,0),total_cents) else 0 end),0)
    into v_online,v_manual,v_refunded from canonical;
  -- Check-in cash/check receipts predate balance allocation IDs. Their gross
  -- amount already lives on the locked balance and must not be erased here.
  v_manual:=greatest(b.paid_manual_cents,v_manual);
  v_refunded:=greatest(b.refunded_cents,v_refunded);
  v_previous:=current_setting('ringmaster.payment_state_write',true);
  perform set_config('ringmaster.payment_state_write','on',true);
  update public.show_exhibitor_balances set paid_online_cents=v_online,paid_manual_cents=v_manual,
    refunded_cents=v_refunded,balance_due_cents=greatest(calculated_total_cents-v_online-v_manual+v_refunded,0),
    payment_status=case when v_online+v_manual-v_refunded>calculated_total_cents then 'overpaid'
      when v_online+v_manual-v_refunded>=calculated_total_cents then 'paid'
      when v_online+v_manual-v_refunded>0 then 'partial' else 'unpaid' end,
    latest_show_payment_id=p.id,latest_checkout_session_id=coalesce(p.checkout_session_id,p.stripe_checkout_session_id),
    latest_payment_intent_id=coalesce(p.payment_intent_id,p.stripe_payment_intent_id),updated_at=now()
    where id=b.id returning * into b;
  perform set_config('ringmaster.payment_state_write',coalesce(v_previous,'off'),true);
  return b;
end;
$$;
revoke all on function public.apply_show_payment_to_balance(uuid) from public,anon,authenticated;
grant execute on function public.apply_show_payment_to_balance(uuid) to service_role;

revoke all on all functions in schema entry_refunds_private from public,anon,authenticated;
revoke all on function public.prepare_entry_refund(uuid,uuid,uuid,uuid[],integer,integer,text,boolean),
  public.get_entry_refund_work(uuid),public.mark_entry_refund_attempt(uuid),
  public.finish_entry_refund(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.prepare_entry_refund(uuid,uuid,uuid,uuid[],integer,integer,text,boolean),
  public.get_entry_refund_work(uuid),public.mark_entry_refund_attempt(uuid),
  public.finish_entry_refund(uuid,text,text,text) to service_role;
