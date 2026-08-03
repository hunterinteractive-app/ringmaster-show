create table public.show_checkin_receipt_deliveries (
  id uuid primary key default extensions.gen_random_uuid(),
  checkin_record_id uuid not null unique references public.show_checkin_records(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'sending', 'sent', 'failed')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  claimed_at timestamptz,
  sent_at timestamptz,
  provider_message_id text,
  failure_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.show_checkin_receipt_deliveries enable row level security;
revoke all on table public.show_checkin_receipt_deliveries from public, anon, authenticated;

create or replace function public.claim_checkin_receipt_delivery(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_record public.show_checkin_records%rowtype;
  v_delivery public.show_checkin_receipt_deliveries%rowtype;
  v_exhibitor public.exhibitors%rowtype;
  v_show public.shows%rowtype;
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now();
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  select * into v_record
  from public.show_checkin_records
  where show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id
  for update;
  if not found or v_record.status <> 'completed' or v_record.receipt_preference <> 'email_receipt' then
    raise exception 'Receipt email is not available.' using errcode = '22023';
  end if;

  select * into v_exhibitor from public.exhibitors where id = v_session.exhibitor_id;
  if nullif(btrim(coalesce(v_exhibitor.email, '')), '') is null then
    raise exception 'No email address is available for this exhibitor.' using errcode = '22023';
  end if;

  insert into public.show_checkin_receipt_deliveries (checkin_record_id)
  values (v_record.id)
  on conflict (checkin_record_id) do nothing;

  select * into v_delivery
  from public.show_checkin_receipt_deliveries
  where checkin_record_id = v_record.id
  for update;

  if v_delivery.status = 'sent' or v_record.receipt_sent_at is not null then
    return jsonb_build_object('already_sent', true);
  end if;
  if v_delivery.status = 'sending' and v_delivery.claimed_at > now() - interval '5 minutes' then
    return jsonb_build_object('in_progress', true);
  end if;

  update public.show_checkin_receipt_deliveries
  set status = 'sending', attempt_count = attempt_count + 1, claimed_at = now(),
      failure_message = null, updated_at = now()
  where id = v_delivery.id;

  select * into v_show from public.shows where id = v_session.show_id;
  return jsonb_build_object(
    'delivery_id', v_delivery.id,
    'email', v_exhibitor.email,
    'show_name', v_show.name,
    'exhibitor_name', coalesce(nullif(v_exhibitor.display_name, ''), trim(coalesce(v_exhibitor.first_name, '') || ' ' || coalesce(v_exhibitor.last_name, ''))),
    'checked_in_at', v_record.completed_at
  );
end;
$$;

create or replace function public.finalize_checkin_receipt_delivery(
  p_delivery_id uuid,
  p_provider_message_id text default null,
  p_failure_message text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery public.show_checkin_receipt_deliveries%rowtype;
begin
  select * into v_delivery from public.show_checkin_receipt_deliveries where id = p_delivery_id for update;
  if not found then raise exception 'Receipt delivery was not found.'; end if;

  if p_provider_message_id is not null then
    update public.show_checkin_receipt_deliveries
    set status = 'sent', sent_at = now(), provider_message_id = p_provider_message_id,
        failure_message = null, updated_at = now()
    where id = p_delivery_id;
    update public.show_checkin_records
    set receipt_sent_at = now(), receipt_provider_message_id = p_provider_message_id, updated_at = now()
    where id = v_delivery.checkin_record_id;
    insert into public.show_checkin_audit_events (show_id, exhibitor_id, checkin_record_id, event_type, actor_type, details)
    select show_id, exhibitor_id, id, 'receipt_email_sent', 'system', jsonb_build_object('provider_message_id', p_provider_message_id)
    from public.show_checkin_records where id = v_delivery.checkin_record_id;
  else
    update public.show_checkin_receipt_deliveries
    set status = 'failed', failure_message = left(coalesce(p_failure_message, 'Unable to send receipt email.'), 500),
        updated_at = now()
    where id = p_delivery_id;
  end if;
end;
$$;

revoke all on function public.claim_checkin_receipt_delivery(text) from public;
grant execute on function public.claim_checkin_receipt_delivery(text) to anon, authenticated, service_role;
revoke all on function public.finalize_checkin_receipt_delivery(uuid, text, text) from public, anon, authenticated;
grant execute on function public.finalize_checkin_receipt_delivery(uuid, text, text) to service_role;
