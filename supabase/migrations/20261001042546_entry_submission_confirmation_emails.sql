-- One immutable confirmation per newly submitted cart; no historical backfill.
create table public.entry_confirmation_emails (
 cart_id uuid primary key references public.entry_carts(id) on delete cascade,
 show_id uuid not null references public.shows(id) on delete cascade,
 snapshot jsonb not null,
 email_payload jsonb,
 status text not null default 'pending' check(status in ('pending','sent','blocked','skipped')),
 attempts integer not null default 0,
 first_attempt_at timestamptz,
 next_attempt_at timestamptz not null default now(),
 lease_token uuid,
 lease_until timestamptz,
 provider_message_id text,
 last_error text,
 created_at timestamptz not null default now(),
 sent_at timestamptz
);
alter table public.entry_confirmation_emails enable row level security;
revoke all on public.entry_confirmation_emails from public,anon,authenticated;
grant all on public.entry_confirmation_emails to service_role;
create index entry_confirmation_pending_idx on public.entry_confirmation_emails(next_attempt_at)
 where status='pending';

create or replace function checkout_private.queue_entry_confirmation()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 c public.entry_carts%rowtype; s public.shows%rowtype;
 recipient text; names text; entry_count integer; due numeric; currency text; balance_count integer;
 blocked_reason text; paid numeric; charges jsonb;
begin
 select * into c from public.entry_carts where id=new.id;
 if c.status <> 'submitted' then return null; end if;
 -- Online registrations are confirmed only after payment finalization.
 if c.selected_payment_timing='online' and c.payment_status <> 'paid' then return null; end if;
 select * into s from public.shows where id=c.show_id;
 select email into recipient from auth.users where id=c.user_id;
 select count(*),string_agg(distinct x.display_name, ', ' order by x.display_name)
 into entry_count,names from public.entries e join public.exhibitors x on x.id=e.exhibitor_id
 where e.source_cart_id=c.id;
 if entry_count=0 then return null; end if;
 select count(*),sum(greatest(balance_due_cents,0)),min(b.currency)
 into balance_count,due,currency from public.show_exhibitor_balances b
 where b.entry_cart_id=c.id and b.source='cart';
 paid := case when c.payment_status='paid' then round(c.payment_amount_total*100) else 0 end;
 if recipient is null or recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
   blocked_reason := 'No valid checkout account email';
 elsif balance_count=0 or currency is null or paid is null then
   blocked_reason := 'Missing authoritative checkout amounts';
 end if;
 -- Paid checkout line items preserve the exact labels and amounts quoted.
 -- Platform/processor deductions are club costs, not extra exhibitor charges.
 if c.payment_status='paid' and c.completed_payment_session_id is not null then
   select coalesce(jsonb_agg(jsonb_build_object('label',label,'amount_cents',amount) order by label),'[]'::jsonb)
   into charges from (
     select coalesce(nullif(label,''),'Fee') label,sum(total_amount_cents) amount
     from public.show_payment_line_items
     where payment_session_id=c.completed_payment_session_id
       and line_type in ('entry_fee','fur_fee','per_show_fee','discount','adjustment','online_fee')
     group by label having sum(total_amount_cents)<>0
   ) lines;
 else
   select coalesce(jsonb_agg(jsonb_build_object('label',label,'amount_cents',amount) order by label),'[]'::jsonb)
   into charges from (
     select label,sum(amount) amount from (
       select x.label,x.amount from public.show_exhibitor_balances b
       cross join lateral (values
         ('Entry fees',b.entries_subtotal_cents),
         ('Fur / Wool fees',b.fur_subtotal_cents),
         ('Per-show fees',b.show_fee_subtotal_cents-coalesce((b.fee_snapshot->>'exhibitor_fee_cents')::integer,0)),
         (coalesce(b.fee_snapshot->>'exhibitor_fee_label','Exhibitor Fee'),coalesce((b.fee_snapshot->>'exhibitor_fee_cents')::integer,0)),
         ('Discount',-b.discount_cents)
       ) x(label,amount) where b.entry_cart_id=c.id and b.source='cart'
       union all
       select name,quantity*unit_price_cents from show_addons_private.selections where cart_id=c.id
     ) items group by label having sum(amount)<>0
   ) lines;
 end if;
 insert into public.entry_confirmation_emails(cart_id,show_id,snapshot,status,last_error)
 values(c.id,c.show_id,jsonb_build_object(
   'to',recipient,'show_name',s.name,'exhibitors',names,'entry_count',entry_count,
   'charges',charges,'paid_cents',paid,'balance_due_cents',due,'currency',upper(currency),
   'payment_timing',c.selected_payment_timing,
   'auto_checkin',coalesce(s.auto_email_checkin_sheets,false),
   'submitted_at',c.submitted_at),
   case when coalesce(s.is_test,false) or coalesce(s.email_sending_disabled,false) then 'skipped'
        when blocked_reason is not null then 'blocked' else 'pending' end,blocked_reason)
 on conflict(cart_id) do nothing;
 return null;
end $$;
revoke all on function checkout_private.queue_entry_confirmation() from public,anon,authenticated;
-- Deferred execution sees the final entries, balances and payment state in the
-- submission transaction. Rolled-back checkouts never leave an email to send.
create constraint trigger entry_cart_confirmation_after_submission
 after update on public.entry_carts deferrable initially deferred for each row
 when (new.status='submitted' and old.status is distinct from new.status)
 execute function checkout_private.queue_entry_confirmation();

create function public.claim_entry_confirmation_emails(p_token uuid)
returns setof public.entry_confirmation_emails language plpgsql security invoker set search_path='' as $$
begin
 update public.entry_confirmation_emails set status='blocked',last_error='Retry window expired; review delivery before resending'
 where status='pending' and (attempts>=12 or first_attempt_at < now()-interval '23 hours')
 and (lease_until is null or lease_until<now());
 return query
 with picked as (
 select cart_id from public.entry_confirmation_emails where status='pending'
 and next_attempt_at<=now() and (lease_until is null or lease_until<now())
 order by created_at for update skip locked limit 10
 )
 update public.entry_confirmation_emails q set lease_token=p_token,lease_until=now()+interval '5 minutes',
 attempts=q.attempts+1,first_attempt_at=coalesce(q.first_attempt_at,now()),next_attempt_at=now()+interval '2 minutes'
 from picked where q.cart_id=picked.cart_id returning q.*;
end $$;
revoke all on function public.claim_entry_confirmation_emails(uuid) from public,anon,authenticated;
grant execute on function public.claim_entry_confirmation_emails(uuid) to service_role;

-- Reuse the existing protected scheduler credentials without exposing them in
-- source or logs. Deploy the worker before applying this migration.
do $$ declare command_text text; begin
 select command into command_text from cron.job where jobname='auto-email-checkin-sheets' limit 1;
 if command_text is not null and position('/auto-email-checkin-sheets' in command_text)>0 then
   perform cron.schedule('send-entry-confirmations','* * * * *',
     replace(command_text,'/auto-email-checkin-sheets','/send-entry-confirmations'));
 end if;
end $$;
