create or replace function public.complete_exhibitor_checkin(
  p_session_token text,
  p_entries_confirmed boolean,
  p_initials text default null,
  p_signature_data text default null,
  p_receipt_preference text default 'no_receipt'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_record public.show_checkin_records%rowtype;
  v_initials text := nullif(btrim(coalesce(p_initials, '')), '');
  v_signature text := nullif(btrim(coalesce(p_signature_data, '')), '');
  v_receipt text := lower(btrim(coalesce(p_receipt_preference, 'no_receipt')));
  v_now timestamptz := now();
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > v_now
  for update;
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled
     or (v_settings.opens_at is not null and v_now < v_settings.opens_at)
     or (v_settings.closes_at is not null and v_now > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;
  if not p_entries_confirmed then
    raise exception 'You must confirm your entries before completing check-in';
  end if;
  if v_settings.require_initials and v_initials is null then
    raise exception 'Initials are required';
  end if;
  if v_settings.require_signature and v_signature is null then
    raise exception 'A signature is required';
  end if;
  if v_receipt not in ('email_receipt', 'no_receipt') then
    raise exception 'Invalid receipt preference';
  end if;

  insert into public.show_checkin_records(show_id, exhibitor_id, status)
  values (v_session.show_id, v_session.exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id) do nothing;
  select * into v_record from public.show_checkin_records
  where show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id
  for update;
  if v_record.status = 'locked' then
    raise exception 'This check-in has been locked by the show secretary';
  end if;

  update public.show_checkin_records
  set status = 'completed', confirmed_at = v_now,
      confirmed_by_type = 'exhibitor', confirmation_initials = v_initials,
      signature_data = v_signature, receipt_preference = v_receipt,
      completed_at = v_now, updated_at = v_now
  where id = v_record.id;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, checkin_record_id, event_type, actor_type, session_id, details
  ) values (
    v_session.show_id, v_session.exhibitor_id, v_record.id,
    'checkin_completed', 'exhibitor_portal', v_session.id,
    jsonb_build_object('receipt_preference', v_receipt, 'has_initials', v_initials is not null, 'has_signature', v_signature is not null)
  );

  return jsonb_build_object('status', 'completed', 'completed_at', v_now);
end;
$$;

revoke all on function public.complete_exhibitor_checkin(text, boolean, text, text, text) from public;
grant execute on function public.complete_exhibitor_checkin(text, boolean, text, text, text)
  to anon, authenticated, service_role;
