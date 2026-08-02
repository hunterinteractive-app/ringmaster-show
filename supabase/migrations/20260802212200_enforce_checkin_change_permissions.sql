-- The public screen hides disabled fields, but the database must enforce the
-- same rule so a caller cannot submit a crafted request for another field.
create or replace function public.submit_exhibitor_checkin_change_request(
  p_session_token text,
  p_entry_id uuid,
  p_request_type text,
  p_requested_changes jsonb default '{}'::jsonb,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_id uuid;
  v_key text;
  v_permission text;
  v_changes jsonb := coalesce(p_requested_changes, '{}'::jsonb);
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now()
  for update;

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  if p_request_type not in ('entry_edit', 'scratch_entry', 'add_entry') then
    raise exception 'Invalid change request type';
  end if;

  if jsonb_typeof(v_changes) <> 'object' then
    raise exception 'Requested changes must be an object';
  end if;

  select * into v_settings
  from public.show_checkin_settings
  where show_id = v_session.show_id;

  if not found or not v_settings.is_enabled then
    raise exception 'Check-in is not available';
  end if;

  if p_entry_id is not null and not exists (
    select 1
    from public.entries e
    where e.id = p_entry_id
      and e.show_id = v_session.show_id
      and e.exhibitor_id = v_session.exhibitor_id
  ) then
    raise exception 'Entry not found';
  end if;

  if p_request_type = 'add_entry' then
    v_permission := coalesce(v_settings.entry_edit_permissions ->> 'add_entry', 'disabled');
    if v_permission not in ('automatic', 'approval') then
      raise exception 'Adding entries is not available through this portal';
    end if;
  end if;

  for v_key in select jsonb_object_keys(v_changes)
  loop
    if v_key not in (
      'ear_number', 'breed', 'variety', 'class', 'sex', 'fur_variety', 'scratch_entry'
    ) then
      raise exception 'This field cannot be changed through the check-in portal';
    end if;

    v_permission := coalesce(v_settings.entry_edit_permissions ->> v_key, 'disabled');
    if v_permission not in ('automatic', 'approval') then
      raise exception 'This field is not available for exhibitor changes';
    end if;
  end loop;

  if p_request_type = 'scratch_entry' then
    v_permission := coalesce(v_settings.entry_edit_permissions ->> 'scratch_entry', 'disabled');
    if v_permission not in ('automatic', 'approval') then
      raise exception 'Scratching entries is not available through this portal';
    end if;
  end if;

  insert into public.show_checkin_change_requests(
    show_id,
    exhibitor_id,
    entry_id,
    request_type,
    requested_changes,
    exhibitor_note
  ) values (
    v_session.show_id,
    v_session.exhibitor_id,
    p_entry_id,
    p_request_type,
    v_changes,
    nullif(btrim(coalesce(p_note, '')), '')
  ) returning id into v_id;

  insert into public.show_checkin_audit_events(
    show_id,
    exhibitor_id,
    event_type,
    actor_type,
    session_id,
    details
  ) values (
    v_session.show_id,
    v_session.exhibitor_id,
    'change_request_submitted',
    'exhibitor_portal',
    v_session.id,
    jsonb_build_object(
      'change_request_id', v_id,
      'entry_id', p_entry_id,
      'request_type', p_request_type,
      'requested_fields', v_changes
    )
  );

  return jsonb_build_object('id', v_id, 'status', 'submitted');
end;
$$;

revoke all on function public.submit_exhibitor_checkin_change_request(text, uuid, text, jsonb, text) from public;
grant execute on function public.submit_exhibitor_checkin_change_request(text, uuid, text, jsonb, text)
  to anon, authenticated, service_role;
