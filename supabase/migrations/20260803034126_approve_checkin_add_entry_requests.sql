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
  v_applied jsonb := '{}'::jsonb;
  v_cart_item_id uuid;
begin
  select * into r from public.show_checkin_change_requests where id = p_request_id for update;
  if not found then raise exception 'Change request not found'; end if;
  if not public.user_can_manage_entries(r.show_id) and not public.user_can_manage_show_settings(r.show_id) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if r.status not in ('submitted', 'pending_review') then
    raise exception 'This request has already been reviewed';
  end if;

  if p_approved and r.request_type = 'add_entry' then
    v_cart_item_id := public.apply_checkin_add_entry(
      r.show_id, r.exhibitor_id, r.requested_changes, r.id
    );
    v_applied := jsonb_build_object('cart_item_id', v_cart_item_id);
  elsif p_approved and r.entry_id is not null and r.requested_changes <> '{}'::jsonb then
    perform public.apply_checkin_entry_changes(
      r.entry_id, r.requested_changes, 'secretary', auth.uid(), r.id
    );
    v_applied := r.requested_changes;
  end if;

  update public.show_checkin_change_requests
  set status = v_status, reviewed_at = now(), reviewed_by_user_id = auth.uid(),
      review_note = nullif(btrim(coalesce(p_review_note, '')), ''),
      applied_changes = case when p_approved then v_applied else '{}'::jsonb end,
      updated_at = now()
  where id = r.id;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, event_type, actor_type, actor_user_id, details
  ) values (
    r.show_id, r.exhibitor_id,
    case when p_approved then 'change_request_approved' else 'change_request_denied' end,
    'secretary', auth.uid(),
    jsonb_build_object('change_request_id', r.id, 'entry_id', r.entry_id,
      'request_type', r.request_type, 'applied_changes', v_applied)
  );
  return jsonb_build_object('id', r.id, 'status', v_status, 'applied_changes', v_applied);
end;
$$;

revoke all on function public.review_checkin_change_request(uuid, boolean, text)
  from public;
grant execute on function public.review_checkin_change_request(uuid, boolean, text)
  to authenticated, service_role;
