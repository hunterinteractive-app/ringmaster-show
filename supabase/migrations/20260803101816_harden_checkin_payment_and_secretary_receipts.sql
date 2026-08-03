create or replace function public.record_checkin_manual_payment(
  p_show_id uuid,
  p_exhibitor_id uuid,
  p_amount_cents integer,
  p_method text,
  p_reference text default null,
  p_receipt_preference text default 'no_receipt'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.show_exhibitor_balances%rowtype;
  pid uuid;
  m text := lower(btrim(coalesce(p_method, '')));
  v_total_due integer := 0;
  v_remaining integer := p_amount_cents;
  v_apply integer;
  v_currency text;
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if p_amount_cents <= 0 or m not in ('cash', 'check', 'digital', 'stripe', 'square', 'paypal') then
    raise exception 'Invalid payment';
  end if;

  for b in
    select * from public.show_exhibitor_balances
    where show_id = p_show_id and exhibitor_id = p_exhibitor_id
    for update
  loop
    v_total_due := v_total_due + greatest(coalesce(b.balance_due_cents, 0), 0);
    v_currency := coalesce(v_currency, b.currency);
  end loop;
  if v_total_due <= 0 then raise exception 'This exhibitor does not have a balance due.'; end if;
  if p_amount_cents > v_total_due then
    raise exception 'Payment amount cannot exceed the outstanding balance.' using errcode = '22023';
  end if;

  insert into public.show_payments(
    show_id, exhibitor_id, currency, status, payment_status, payment_method,
    payment_method_type, payment_type, provider, amount_cents, total_cents, paid_at, metadata
  ) values (
    p_show_id, p_exhibitor_id, coalesce(v_currency, 'usd'), 'paid', 'paid', m,
    m, 'manual', m, p_amount_cents, p_amount_cents, now(),
    jsonb_build_object('reference', p_reference, 'receipt_preference', p_receipt_preference, 'source', 'checkin')
  ) returning id into pid;

  for b in
    select * from public.show_exhibitor_balances
    where show_id = p_show_id and exhibitor_id = p_exhibitor_id and balance_due_cents > 0
    order by updated_at desc
  loop
    exit when v_remaining <= 0;
    v_apply := least(v_remaining, b.balance_due_cents);
    update public.show_exhibitor_balances
    set paid_manual_cents = paid_manual_cents + v_apply,
        balance_due_cents = greatest(0, calculated_total_cents - paid_online_cents - (paid_manual_cents + v_apply) + refunded_cents),
        payment_status = case when calculated_total_cents <= paid_online_cents + paid_manual_cents + v_apply then 'paid' else 'partial' end,
        updated_at = now()
    where id = b.id;
    v_remaining := v_remaining - v_apply;
  end loop;
  if v_remaining <> 0 then raise exception 'Payment could not be applied to the outstanding balance.'; end if;

  insert into public.show_checkin_audit_events(show_id, exhibitor_id, event_type, actor_type, actor_user_id, details)
  values(p_show_id, p_exhibitor_id, 'manual_payment_recorded', 'secretary', auth.uid(), jsonb_build_object('payment_id', pid, 'amount_cents', p_amount_cents, 'method', m));
  return jsonb_build_object('payment_id', pid, 'amount_cents', p_amount_cents);
end;
$$;

create or replace function public.complete_exhibitor_checkin_by_secretary_with_receipt(
  p_show_id uuid,
  p_exhibitor_id uuid,
  p_entries_confirmed boolean,
  p_initials text default null,
  p_signature_data text default null,
  p_note text default null,
  p_receipt_preference text default 'no_receipt'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.show_checkin_records%rowtype;
  v_now timestamptz := now();
  v_receipt text := lower(btrim(coalesce(p_receipt_preference, 'no_receipt')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in.' using errcode = '42501';
  end if;
  if not p_entries_confirmed then raise exception 'Confirm the exhibitor''s entries before completing check-in.'; end if;
  if v_receipt not in ('email_receipt', 'no_receipt') then raise exception 'Invalid receipt preference.'; end if;
  if not exists (select 1 from public.entries where show_id = p_show_id and exhibitor_id = p_exhibitor_id) then
    raise exception 'This exhibitor does not have entries in this show.';
  end if;
  insert into public.show_checkin_records (show_id, exhibitor_id, status)
  values (p_show_id, p_exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id) do nothing;
  select * into v_record from public.show_checkin_records
  where show_id = p_show_id and exhibitor_id = p_exhibitor_id for update;
  if v_record.status = 'locked' then raise exception 'This check-in has been locked.'; end if;

  update public.show_checkin_records
  set status = 'completed', confirmed_at = v_now, confirmed_by_type = 'secretary', confirmed_by_user_id = auth.uid(),
      confirmation_initials = nullif(btrim(coalesce(p_initials, '')), ''),
      signature_data = nullif(btrim(coalesce(p_signature_data, '')), ''),
      receipt_preference = v_receipt, completed_at = v_now, updated_at = v_now,
      receipt_sent_at = null, receipt_provider_message_id = null
  where id = v_record.id;
  insert into public.show_checkin_audit_events (show_id, exhibitor_id, checkin_record_id, event_type, actor_type, actor_user_id, details)
  values (p_show_id, p_exhibitor_id, v_record.id, 'checkin_completed_by_secretary', 'secretary', auth.uid(),
    jsonb_build_object('note', nullif(btrim(coalesce(p_note, '')), ''), 'receipt_preference', v_receipt));
  return jsonb_build_object('id', v_record.id, 'status', 'completed', 'completed_at', v_now, 'completed_by', 'secretary');
end;
$$;

create or replace function public.claim_checkin_receipt_delivery_by_staff(p_checkin_record_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.show_checkin_records%rowtype;
  v_delivery public.show_checkin_receipt_deliveries%rowtype;
  v_exhibitor public.exhibitors%rowtype;
  v_show public.shows%rowtype;
begin
  select * into v_record from public.show_checkin_records where id = p_checkin_record_id for update;
  if not found then raise exception 'Check-in record not found.' using errcode = '22023'; end if;
  if not public.user_can_manage_entries(v_record.show_id)
     and not public.user_can_manage_show_settings(v_record.show_id) then
    raise exception 'You do not have permission to send this receipt.' using errcode = '42501';
  end if;
  if v_record.status <> 'completed' or v_record.receipt_preference <> 'email_receipt' then
    raise exception 'Receipt email is not available.' using errcode = '22023';
  end if;
  select * into v_exhibitor from public.exhibitors where id = v_record.exhibitor_id;
  if nullif(btrim(coalesce(v_exhibitor.email, '')), '') is null then raise exception 'No email address is available for this exhibitor.'; end if;
  insert into public.show_checkin_receipt_deliveries(checkin_record_id) values(v_record.id) on conflict(checkin_record_id) do nothing;
  select * into v_delivery from public.show_checkin_receipt_deliveries where checkin_record_id = v_record.id for update;
  if v_delivery.status = 'sent' or v_record.receipt_sent_at is not null then return jsonb_build_object('already_sent', true); end if;
  if v_delivery.status = 'sending' and v_delivery.claimed_at > now() - interval '5 minutes' then return jsonb_build_object('in_progress', true); end if;
  update public.show_checkin_receipt_deliveries
  set status = 'sending', attempt_count = attempt_count + 1, claimed_at = now(), failure_message = null, updated_at = now()
  where id = v_delivery.id;
  select * into v_show from public.shows where id = v_record.show_id;
  return jsonb_build_object('delivery_id', v_delivery.id, 'email', v_exhibitor.email, 'show_name', v_show.name,
    'exhibitor_name', coalesce(nullif(v_exhibitor.display_name, ''), trim(coalesce(v_exhibitor.first_name, '') || ' ' || coalesce(v_exhibitor.last_name, ''))),
    'checked_in_at', v_record.completed_at);
end;
$$;

revoke all on function public.complete_exhibitor_checkin_by_secretary_with_receipt(uuid, uuid, boolean, text, text, text, text) from public, anon;
grant execute on function public.complete_exhibitor_checkin_by_secretary_with_receipt(uuid, uuid, boolean, text, text, text, text) to authenticated, service_role;
revoke all on function public.claim_checkin_receipt_delivery_by_staff(uuid) from public, anon;
grant execute on function public.claim_checkin_receipt_delivery_by_staff(uuid) to authenticated, service_role;
