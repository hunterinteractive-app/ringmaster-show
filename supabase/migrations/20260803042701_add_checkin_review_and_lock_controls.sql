create or replace function public.update_show_checkin_record_status(
  p_checkin_record_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.show_checkin_records%rowtype;
  v_status text := lower(btrim(coalesce(p_status, '')));
  v_now timestamptz := now();
begin
  select * into v_record from public.show_checkin_records where id = p_checkin_record_id for update;
  if not found then raise exception 'Check-in record not found.' using errcode = '22023'; end if;
  if not public.user_can_manage_entries(v_record.show_id)
     and not public.user_can_manage_show_settings(v_record.show_id) then
    raise exception 'You do not have permission to update this check-in.' using errcode = '42501';
  end if;
  if v_record.status = 'locked' then
    raise exception 'This check-in is locked and cannot be changed.' using errcode = '22023';
  end if;

  if v_status = 'reviewed_by_secretary' then
    if v_record.status <> 'completed' then
      raise exception 'Only completed check-ins can be reviewed.' using errcode = '22023';
    end if;
    update public.show_checkin_records
    set status = 'reviewed_by_secretary', reviewed_at = v_now, reviewed_by_user_id = auth.uid(), updated_at = v_now
    where id = v_record.id;
  elsif v_status = 'locked' then
    if v_record.status not in ('completed', 'reviewed_by_secretary') then
      raise exception 'Only completed check-ins can be locked.' using errcode = '22023';
    end if;
    update public.show_checkin_records
    set status = 'locked', locked_at = v_now, locked_by_user_id = auth.uid(), updated_at = v_now
    where id = v_record.id;
  else
    raise exception 'Invalid check-in status.' using errcode = '22023';
  end if;

  insert into public.show_checkin_audit_events (
    show_id, exhibitor_id, checkin_record_id, event_type, actor_type, actor_user_id, details
  ) values (
    v_record.show_id, v_record.exhibitor_id, v_record.id,
    case when v_status = 'locked' then 'checkin_locked' else 'checkin_reviewed' end,
    'secretary', auth.uid(), jsonb_build_object('previous_status', v_record.status, 'new_status', v_status)
  );

  return jsonb_build_object('id', v_record.id, 'status', v_status);
end;
$$;

revoke all on function public.update_show_checkin_record_status(uuid, text) from public, anon;
grant execute on function public.update_show_checkin_record_status(uuid, text) to authenticated, service_role;

create or replace function public.prevent_locked_checkin_change_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.show_checkin_records
    where show_id = new.show_id and exhibitor_id = new.exhibitor_id and status = 'locked'
  ) then
    raise exception 'This check-in is locked and cannot accept additional changes.' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_locked_checkin_change_request on public.show_checkin_change_requests;
create trigger prevent_locked_checkin_change_request
before insert on public.show_checkin_change_requests
for each row execute function public.prevent_locked_checkin_change_request();

revoke all on function public.prevent_locked_checkin_change_request() from public, anon, authenticated;
