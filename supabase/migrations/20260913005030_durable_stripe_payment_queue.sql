-- Verified Stripe notifications are durable before acknowledgement. A short
-- database worker commits entries, ledger and completion together. A killed
-- worker rolls the entire transaction back and leaves the event ready to retry.
create schema if not exists payment_processing_private;
revoke all on schema payment_processing_private from public, anon, authenticated;

create table payment_processing_private.stripe_events (
  event_id text primary key,
  event_row_id uuid not null unique references public.show_payment_events(id) on delete cascade,
  event_type text not null,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  state text not null default 'pending' check (state in ('pending','completed','blocked')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  last_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table payment_processing_private.stripe_events enable row level security;
revoke all on payment_processing_private.stripe_events from public, anon, authenticated, service_role;
create index stripe_events_ready_idx on payment_processing_private.stripe_events(next_attempt_at, event_id) where state = 'pending';

create or replace function public.enqueue_stripe_payment_event(p_event_id text, p_event_type text, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_event public.show_payment_events%rowtype;
  v_queue payment_processing_private.stripe_events%rowtype;
  v_inserted boolean;
  v_attempt uuid;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode = '42501';
  end if;
  if nullif(btrim(p_event_id),'') is null or length(p_event_id)>255
     or nullif(btrim(p_event_type),'') is null or length(p_event_type)>255
     or p_payload is null or jsonb_typeof(p_payload)<>'object' or pg_column_size(p_payload)>16384 then
    raise exception 'Invalid verified payment event' using errcode = '22023';
  end if;
  v_attempt := nullif(p_payload->>'payment_session_id','')::uuid;
  insert into public.show_payment_events(provider,event_id,event_type,payload,processing_status,received_at,payment_session_id,provider_payment_id)
  values ('stripe',p_event_id,p_event_type,
    jsonb_build_object('stripe_object_id',p_payload->>'object_id','stripe_account_id',p_payload->>'account','livemode',p_payload->'livemode'),
    'received',now(),v_attempt,p_payload->>'payment_intent')
  on conflict (provider,event_id) do nothing;
  select * into strict v_event from public.show_payment_events where provider='stripe' and event_id=p_event_id;
  if v_event.event_type is distinct from p_event_type then
    raise exception 'Payment event identity changed' using errcode = '22023';
  end if;
  insert into payment_processing_private.stripe_events(event_id,event_row_id,event_type,payload,state,completed_at)
  values (p_event_id,v_event.id,p_event_type,p_payload,
    case when v_event.processing_status in ('processed','ignored') then 'completed' else 'pending' end,
    case when v_event.processing_status in ('processed','ignored') then now() end)
  on conflict (event_id) do nothing returning * into v_queue;
  v_inserted := found;
  if not v_inserted then
    select * into strict v_queue from payment_processing_private.stripe_events where event_id=p_event_id;
    if v_queue.payload is distinct from p_payload or v_queue.event_type is distinct from p_event_type then
      raise exception 'Payment event payload changed' using errcode = '22023';
    end if;
  end if;
  return jsonb_build_object('durably_queued',true,'duplicate',not v_inserted,
    'processing_status',case when v_queue.state='completed' then 'processed' else v_queue.state end);
end;
$$;
revoke all on function public.enqueue_stripe_payment_event(text,text,jsonb) from public, anon, authenticated;
grant execute on function public.enqueue_stripe_payment_event(text,text,jsonb) to service_role;

-- Called only by the private worker. The input is the minimal signed event,
-- never browser-supplied assertions that a payment was made.
create function payment_processing_private.apply_stripe_event(p_type text, p jsonb)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare
  a public.show_payment_sessions%rowtype;
  v_cart uuid := nullif(p->>'cart_id','')::uuid;
  v_id uuid := nullif(p->>'payment_session_id','')::uuid;
  v_intent text := nullif(p->>'payment_intent','');
begin
  if p_type not in ('checkout.session.completed','checkout.session.expired','payment_intent.payment_failed') then return null; end if;
  if v_id is not null then
    select * into a from public.show_payment_sessions where id=v_id;
  elsif p_type='payment_intent.payment_failed' then
    select s.* into a from public.show_payment_sessions s join public.entry_carts c on c.active_payment_session_id=s.id where c.id=v_cart;
  else
    select * into a from public.show_payment_sessions where provider='stripe' and provider_session_id=p->>'object_id';
  end if;
  if a.id is null then raise exception 'Payment attempt not found'; end if;
  if a.provider <> 'stripe' or (v_cart is not null and a.cart_id is distinct from v_cart)
     or (nullif(p->>'provider','') is not null and p->>'provider'<>'stripe') then
    raise exception 'Payment identity mismatch' using errcode='22023';
  end if;
  if p_type='payment_intent.payment_failed' then
    -- A payment intent can succeed later on the same Checkout Session.
    if v_intent is null or (a.provider_payment_id is not null and a.provider_payment_id<>v_intent) then
      raise exception 'Stripe payment intent does not match the attempt' using errcode='22023';
    end if;
    return a.id;
  end if;
  if a.provider_session_id is distinct from p->>'object_id' then
    raise exception 'Stripe session does not match the attempt' using errcode='22023';
  end if;
  if p_type='checkout.session.expired' then
    if a.attempt_status<>'finalized' then
      perform public.mark_payment_attempt_terminal(a.id,'stripe','expired','checkout_session_expired','Stripe Checkout Session expired.',null);
    end if;
    return a.id;
  end if;
  if (nullif(p->>'quote_hash','') is null and coalesce((a.metadata->>'legacy_backfill')::boolean,false) is not true)
     or (nullif(p->>'quote_hash','') is not null and a.quote_hash is distinct from p->>'quote_hash')
     or (p->>'payment_status') is distinct from 'paid'
     or (p->>'amount_total')::integer is distinct from a.expected_amount_cents
     or lower(p->>'currency') is distinct from lower(a.expected_currency)
     or v_intent is null
     or (a.provider_payment_id is not null and a.provider_payment_id<>v_intent) then
    raise exception 'Paid event does not match the saved quote' using errcode='22023';
  end if;
  perform public.finalize_entry_cart_paid(a.cart_id,a.id,'stripe',v_intent,(p->>'amount_total')::integer,lower(p->>'currency'));
  return a.id;
end;
$$;
revoke all on function payment_processing_private.apply_stripe_event(text,jsonb) from public, anon, authenticated, service_role;

create function payment_processing_private.process_stripe_events(p_limit integer default 25)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  q payment_processing_private.stripe_events%rowtype;
  v_session uuid;
  v_done integer := 0;
  v_failed integer := 0;
  v_claims text := current_setting('request.jwt.claims',true);
  v_message text;
  v_state text;
begin
  -- No callers can set the elevated identity: only this private cron worker
  -- (or the service-only wrapper owned by postgres) can enter this function.
  if current_user not in ('postgres','supabase_admin') then
    raise exception 'Private worker required' using errcode='42501';
  end if;
  if p_limit not between 1 and 100 then raise exception 'Invalid worker batch size'; end if;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  for q in select * from payment_processing_private.stripe_events
    where state='pending' and next_attempt_at<=now()
    order by next_attempt_at,event_id limit p_limit for update skip locked
  loop
    begin
      v_session := payment_processing_private.apply_stripe_event(q.event_type,q.payload);
      update public.show_payment_events set
        processing_status=case when v_session is null then 'ignored' else 'processed' end,
        payment_session_id=coalesce(payment_session_id,v_session),
        processing_error=null,processed_at=now() where id=q.event_row_id;
      update payment_processing_private.stripe_events set state='completed',attempts=attempts+1,
        last_error=null,completed_at=now() where event_id=q.event_id;
      v_done := v_done+1;
    exception when others then
      get stacked diagnostics v_message=message_text,v_state=returned_sqlstate;
      update payment_processing_private.stripe_events set
        attempts=attempts+1,
        state=case when q.attempts+1>=10 or v_state in ('22023','22P02','23514') then 'blocked' else 'pending' end,
        next_attempt_at=now()+make_interval(secs=>least(300,power(2,least(q.attempts,8))::integer)),
        last_error=left(v_message,1000) where event_id=q.event_id;
      update public.show_payment_events set processing_status='failed',processing_error=left(v_message,1000),processed_at=now()
        where id=q.event_row_id;
      v_failed := v_failed+1;
    end;
  end loop;
  perform set_config('request.jwt.claims',coalesce(v_claims,''),true);
  return jsonb_build_object('completed',v_done,'failed',v_failed);
exception when others then
  perform set_config('request.jwt.claims',coalesce(v_claims,''),true);
  raise;
end;
$$;
revoke all on function payment_processing_private.process_stripe_events(integer) from public, anon, authenticated, service_role;

create function public.process_pending_stripe_payment_events(p_limit integer default 25)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  return payment_processing_private.process_stripe_events(p_limit);
end;
$$;
revoke all on function public.process_pending_stripe_payment_events(integer) from public, anon, authenticated;
grant execute on function public.process_pending_stripe_payment_events(integer) to service_role;

create function public.get_stripe_payment_queue_health()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'Backend authorization required' using errcode='42501'; end if;
  return (select jsonb_build_object('pending',count(*) filter(where state='pending'),
    'retrying',count(*) filter(where state='pending' and attempts>0),
    'blocked',count(*) filter(where state='blocked'),
    'oldest_pending_at',min(created_at) filter(where state='pending')) from payment_processing_private.stripe_events where state<>'completed');
end;
$$;
revoke all on function public.get_stripe_payment_queue_health() from public, anon, authenticated;
grant execute on function public.get_stripe_payment_queue_health() to service_role;

select cron.schedule('process-stripe-payment-events','1 second',
  $cron$select payment_processing_private.process_stripe_events(25);$cron$);

-- The existing cart-item uniqueness index excludes rows with null item/kind,
-- so it cannot support a cart-wide paid-entry count. Polling must stay indexed.
create index if not exists entries_source_cart_payment_idx
  on public.entries(source_cart_id,payment_session_id) where source_cart_id is not null;

-- Owners can confirm their own saved registration without trusting a redirect
-- query parameter or exposing queue contents and provider payloads.
create function public.get_stripe_registration_status(p_checkout_session_id text default null, p_cart_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  a public.show_payment_sessions%rowtype;
  c public.entry_carts%rowtype;
  v_expected integer;
  v_actual integer;
  v_payments integer;
  v_paid integer;
  v_complete boolean;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  if nullif(p_checkout_session_id,'') is null and p_cart_id is null then raise exception 'Payment reference required' using errcode='22023'; end if;
  select s.* into a from public.show_payment_sessions s join public.entry_carts cart on cart.id=s.cart_id
  where s.provider='stripe' and cart.user_id=auth.uid()
    and (p_checkout_session_id is null or s.provider_session_id=p_checkout_session_id)
    and (p_cart_id is null or s.cart_id=p_cart_id)
  order by s.created_at desc limit 1;
  if a.id is null then raise exception 'Payment unavailable for this account' using errcode='42501'; end if;
  select * into strict c from public.entry_carts where id=a.cart_id;
  if a.attempt_status<>'finalized' or c.status<>'submitted' or c.payment_status is distinct from 'paid' then
    return jsonb_build_object('completed',false,'attempt_status',a.attempt_status);
  end if;
  select count(*) into v_expected from public.entry_cart_items where cart_id=c.id;
  select count(*) into v_actual from public.entries where source_cart_id=c.id and payment_session_id=a.id and payment_status='paid';
  select count(*),count(*) filter(where payment_status='paid') into v_payments,v_paid from public.show_payments where payment_session_id=a.id;
  v_complete := a.attempt_status='finalized' and c.status='submitted' and c.payment_status='paid'
    and c.completed_payment_session_id=a.id and v_expected>0 and v_actual=v_expected and v_payments>0 and v_paid=v_payments
    and not exists (select 1 from public.entry_cart_items i where i.cart_id=c.id and not exists (
      select 1 from public.entries e where e.source_cart_id=c.id and e.source_cart_item_id=i.id
        and e.payment_session_id=a.id and e.payment_status='paid'
        and e.animal_id is not distinct from i.animal_id and e.exhibitor_id=i.exhibitor_id and e.section_id=i.section_id
        and e.cart_entry_kind=case when coalesce(i.is_fur,false) then 'fur' else 'entry' end));
  return jsonb_build_object('completed',v_complete,'attempt_status',a.attempt_status,
    'expected_entries',v_expected,'saved_paid_entries',v_actual,'payment_records',v_payments,'paid_records',v_paid);
end;
$$;
revoke all on function public.get_stripe_registration_status(text,uuid) from public, anon;
grant execute on function public.get_stripe_registration_status(text,uuid) to authenticated;
