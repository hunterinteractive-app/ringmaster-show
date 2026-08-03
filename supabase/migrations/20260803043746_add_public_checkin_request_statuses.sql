create or replace function public.get_exhibitor_checkin_change_requests(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
begin
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now();
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'request_type', r.request_type,
      'status', r.status,
      'requested_changes', r.requested_changes,
      'exhibitor_note', r.exhibitor_note,
      'review_note', r.review_note,
      'created_at', r.created_at,
      'entry_tattoo', e.tattoo
    ) order by r.created_at desc)
    from public.show_checkin_change_requests r
    left join public.entries e on e.id = r.entry_id
    where r.show_id = v_session.show_id and r.exhibitor_id = v_session.exhibitor_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.cancel_exhibitor_checkin_change_request(
  p_session_token text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_request public.show_checkin_change_requests%rowtype;
begin
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now()
  for update;
  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  select * into v_request from public.show_checkin_change_requests
  where id = p_request_id and show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id
  for update;
  if not found then raise exception 'Change request not found.' using errcode = '22023'; end if;
  if v_request.status not in ('submitted', 'pending_payment', 'pending_review') then
    raise exception 'This request can no longer be cancelled.' using errcode = '22023';
  end if;

  update public.show_checkin_change_requests
  set status = 'cancelled', updated_at = now()
  where id = v_request.id;
  insert into public.show_checkin_audit_events (
    show_id, exhibitor_id, event_type, actor_type, session_id, details
  ) values (
    v_session.show_id, v_session.exhibitor_id, 'change_request_cancelled', 'exhibitor_portal', v_session.id,
    jsonb_build_object('change_request_id', v_request.id)
  );
  return jsonb_build_object('id', v_request.id, 'status', 'cancelled');
end;
$$;

revoke all on function public.get_exhibitor_checkin_change_requests(text) from public;
grant execute on function public.get_exhibitor_checkin_change_requests(text) to anon, authenticated, service_role;
revoke all on function public.cancel_exhibitor_checkin_change_request(text, uuid) from public;
grant execute on function public.cancel_exhibitor_checkin_change_request(text, uuid) to anon, authenticated, service_role;
