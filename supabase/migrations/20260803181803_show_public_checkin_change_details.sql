create or replace function public.get_exhibitor_checkin_change_requests(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex'
  ) and revoked_at is null and expires_at > now();

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id,
      'entry_id', r.entry_id,
      'request_type', r.request_type,
      'status', r.status,
      'requested_changes', r.requested_changes,
      'original_values', r.original_values,
      'applied_changes', r.applied_changes,
      'exhibitor_note', r.exhibitor_note,
      'review_note', r.review_note,
      'fee_cents', r.fee_cents,
      'created_at', r.created_at,
      'entry_tattoo', e.tattoo
    ) order by r.created_at desc)
    from public.show_checkin_change_requests r
    left join public.entries e on e.id = r.entry_id
    where r.show_id = v_session.show_id
      and r.exhibitor_id = v_session.exhibitor_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_exhibitor_checkin_change_requests(text) from public;
grant execute on function public.get_exhibitor_checkin_change_requests(text)
  to anon, authenticated, service_role;
