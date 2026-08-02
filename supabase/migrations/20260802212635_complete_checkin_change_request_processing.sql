alter table public.show_checkin_change_requests
  add column if not exists original_values jsonb not null default '{}'::jsonb,
  add column if not exists applied_changes jsonb not null default '{}'::jsonb;

-- Private-in-practice helper: both public request functions use this exact
-- path so entry data, scratch status, and audit history stay consistent.
create or replace function public.apply_checkin_entry_changes(
  p_entry_id uuid,
  p_changes jsonb,
  p_actor_type text,
  p_actor_user_id uuid default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.entries%rowtype;
  v_show public.shows%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_is_scratched boolean;
begin
  select * into v_entry from public.entries where id = p_entry_id for update;
  if not found then raise exception 'Entry not found'; end if;
  select * into v_show from public.shows where id = v_entry.show_id;
  if not found or coalesce(v_show.is_locked, false) then
    raise exception 'Show is locked. Changes are not allowed.' using errcode = '55000';
  end if;

  v_before := jsonb_build_object(
    'ear_number', v_entry.tattoo,
    'breed', v_entry.breed,
    'variety', v_entry.variety,
    'class', v_entry.class_name,
    'sex', v_entry.sex,
    'fur_variety', v_entry.fur_variety,
    'scratch_entry', v_entry.scratched_at is not null or lower(coalesce(v_entry.status, '')) = 'scratched'
  );
  v_is_scratched := case
    when p_changes ? 'scratch_entry' then coalesce((p_changes ->> 'scratch_entry')::boolean, false)
    else (v_entry.scratched_at is not null or lower(coalesce(v_entry.status, '')) = 'scratched')
  end;

  update public.entries
  set tattoo = case when p_changes ? 'ear_number' then nullif(btrim(p_changes ->> 'ear_number'), '') else v_entry.tattoo end,
      breed = case when p_changes ? 'breed' then nullif(btrim(p_changes ->> 'breed'), '') else v_entry.breed end,
      variety = case when p_changes ? 'variety' then nullif(btrim(p_changes ->> 'variety'), '') else v_entry.variety end,
      class_name = case when p_changes ? 'class' then nullif(btrim(p_changes ->> 'class'), '') else v_entry.class_name end,
      sex = case when p_changes ? 'sex' then nullif(btrim(p_changes ->> 'sex'), '') else v_entry.sex end,
      fur_variety = case when p_changes ? 'fur_variety' then nullif(btrim(p_changes ->> 'fur_variety'), '') else v_entry.fur_variety end,
      status = case when v_is_scratched then 'scratched' else v_entry.status end,
      scratched_at = case when v_is_scratched then coalesce(v_entry.scratched_at, now()) else v_entry.scratched_at end,
      updated_at = now()
  where id = v_entry.id;

  select jsonb_build_object(
    'ear_number', e.tattoo,
    'breed', e.breed,
    'variety', e.variety,
    'class', e.class_name,
    'sex', e.sex,
    'fur_variety', e.fur_variety,
    'scratch_entry', e.scratched_at is not null or lower(coalesce(e.status, '')) = 'scratched'
  ) into v_after from public.entries e where e.id = v_entry.id;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, event_type, actor_type, actor_user_id, details
  ) values (
    v_entry.show_id, v_entry.exhibitor_id, 'checkin_entry_change_applied',
    p_actor_type, p_actor_user_id,
    jsonb_build_object('entry_id', v_entry.id, 'change_request_id', p_request_id, 'before', v_before, 'after', v_after)
  );
  return jsonb_build_object('before', v_before, 'after', v_after);
end;
$$;
revoke all on function public.apply_checkin_entry_changes(uuid, jsonb, text, uuid, uuid) from public;

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
  v_entry public.entries%rowtype;
  v_id uuid;
  v_key text;
  v_permission text;
  v_changes jsonb := coalesce(p_requested_changes, '{}'::jsonb);
  v_automatic jsonb := '{}'::jsonb;
  v_approval jsonb := '{}'::jsonb;
  v_original jsonb := '{}'::jsonb;
  v_status text;
begin
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now() for update;
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501'; end if;
  if p_request_type not in ('entry_edit', 'scratch_entry', 'add_entry') then raise exception 'Invalid change request type'; end if;
  if jsonb_typeof(v_changes) <> 'object' then raise exception 'Requested changes must be an object'; end if;

  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled then raise exception 'Check-in is not available'; end if;
  if p_entry_id is null and p_request_type <> 'add_entry' then raise exception 'Entry is required'; end if;
  if p_entry_id is not null then
    select * into v_entry from public.entries where id = p_entry_id and show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id;
    if not found then raise exception 'Entry not found'; end if;
    v_original := jsonb_build_object('ear_number', v_entry.tattoo, 'breed', v_entry.breed, 'variety', v_entry.variety, 'class', v_entry.class_name, 'sex', v_entry.sex, 'fur_variety', v_entry.fur_variety, 'scratch_entry', v_entry.scratched_at is not null or lower(coalesce(v_entry.status, '')) = 'scratched');
  end if;

  if p_request_type = 'add_entry' then
    v_permission := coalesce(v_settings.entry_edit_permissions ->> 'add_entry', 'disabled');
    if v_permission not in ('automatic', 'approval') then raise exception 'Adding entries is not available through this portal'; end if;
  end if;

  for v_key in select jsonb_object_keys(v_changes) loop
    if v_key not in ('ear_number', 'breed', 'variety', 'class', 'sex', 'fur_variety', 'scratch_entry') then raise exception 'This field cannot be changed through the check-in portal'; end if;
    if v_key = 'scratch_entry' and coalesce((v_changes ->> v_key)::boolean, false) is not true then raise exception 'Only scratching an entry can be requested through this portal'; end if;
    v_permission := coalesce(v_settings.entry_edit_permissions ->> v_key, 'disabled');
    if v_permission not in ('automatic', 'approval') then raise exception 'This field is not available for exhibitor changes'; end if;
    if v_permission = 'automatic' then v_automatic := v_automatic || jsonb_build_object(v_key, v_changes -> v_key); else v_approval := v_approval || jsonb_build_object(v_key, v_changes -> v_key); end if;
  end loop;

  v_status := case when v_approval <> '{}'::jsonb then 'pending_review' when v_automatic <> '{}'::jsonb then 'approved' else 'submitted' end;
  insert into public.show_checkin_change_requests(show_id, exhibitor_id, entry_id, request_type, requested_changes, original_values, applied_changes, exhibitor_note, status, reviewed_at)
  values(v_session.show_id, v_session.exhibitor_id, p_entry_id, p_request_type, v_approval, v_original, v_automatic, nullif(btrim(coalesce(p_note, '')), ''), v_status, case when v_status = 'approved' then now() else null end)
  returning id into v_id;

  if v_automatic <> '{}'::jsonb then
    perform public.apply_checkin_entry_changes(p_entry_id, v_automatic, 'exhibitor_portal', null, v_id);
  end if;
  insert into public.show_checkin_audit_events(show_id, exhibitor_id, event_type, actor_type, session_id, details)
  values(v_session.show_id, v_session.exhibitor_id, 'change_request_submitted', 'exhibitor_portal', v_session.id, jsonb_build_object('change_request_id', v_id, 'entry_id', p_entry_id, 'automatic_changes', v_automatic, 'pending_review_changes', v_approval));
  return jsonb_build_object('id', v_id, 'status', v_status, 'automatic_changes', v_automatic, 'pending_review_changes', v_approval);
end;
$$;
revoke all on function public.submit_exhibitor_checkin_change_request(text, uuid, text, jsonb, text) from public;
grant execute on function public.submit_exhibitor_checkin_change_request(text, uuid, text, jsonb, text) to anon, authenticated, service_role;

create or replace function public.review_checkin_change_request(
  p_request_id uuid,
  p_approved boolean,
  p_review_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.show_checkin_change_requests%rowtype;
  v_status text := case when p_approved then 'approved' else 'denied' end;
begin
  select * into r from public.show_checkin_change_requests where id = p_request_id for update;
  if not found then raise exception 'Change request not found'; end if;
  if not public.user_can_manage_entries(r.show_id) and not public.user_can_manage_show_settings(r.show_id) then raise exception 'Permission denied' using errcode = '42501'; end if;
  if r.status not in ('submitted', 'pending_review') then raise exception 'This request has already been reviewed'; end if;
  if p_approved and r.entry_id is not null and r.requested_changes <> '{}'::jsonb then
    perform public.apply_checkin_entry_changes(r.entry_id, r.requested_changes, 'secretary', auth.uid(), r.id);
  end if;
  update public.show_checkin_change_requests
  set status = v_status, reviewed_at = now(), reviewed_by_user_id = auth.uid(), review_note = nullif(btrim(coalesce(p_review_note, '')), ''), updated_at = now()
  where id = r.id;
  insert into public.show_checkin_audit_events(show_id, exhibitor_id, event_type, actor_type, actor_user_id, details)
  values(r.show_id, r.exhibitor_id, case when p_approved then 'change_request_approved' else 'change_request_denied' end, 'secretary', auth.uid(), jsonb_build_object('change_request_id', r.id, 'entry_id', r.entry_id, 'applied_changes', case when p_approved then r.requested_changes else '{}'::jsonb end));
  return jsonb_build_object('id', r.id, 'status', v_status, 'applied_changes', case when p_approved then r.requested_changes else '{}'::jsonb end);
end;
$$;
revoke all on function public.review_checkin_change_request(uuid, boolean, text) from public;
grant execute on function public.review_checkin_change_request(uuid, boolean, text) to authenticated, service_role;
