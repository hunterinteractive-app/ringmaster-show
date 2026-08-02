-- One authoritative scratch/restore operation for exhibitor and staff flows.
-- It keeps status and scratched_at consistent for every report/result consumer.

create or replace function public.set_entry_scratch_state(
  p_entry_id uuid,
  p_is_scratched boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.entries%rowtype;
  v_show public.shows%rowtype;
  v_is_service boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
  v_is_manager boolean := false;
  v_actor_type text;
  v_now timestamptz := now();
begin
  select * into v_entry
  from public.entries
  where id = p_entry_id
  for update;

  if not found then
    raise exception 'Entry not found' using errcode = 'P0002';
  end if;

  select * into v_show
  from public.shows
  where id = v_entry.show_id;

  if not found then
    raise exception 'Show not found' using errcode = 'P0002';
  end if;
  if coalesce(v_show.is_locked, false) then
    raise exception 'Show is locked. Changes are not allowed.' using errcode = '55000';
  end if;

  v_is_manager := public.user_can_manage_entries(v_entry.show_id)
    or public.user_can_manage_show_settings(v_entry.show_id);

  if not v_is_service
     and auth.uid() is distinct from v_entry.exhibitor_user_id
     and not v_is_manager then
    raise exception 'You do not have permission to update this entry'
      using errcode = '42501';
  end if;

  -- An exhibitor may withdraw at any time, but a restored entry must again be
  -- eligible under the show's entry deadline.
  if not p_is_scratched
     and v_show.entry_close_at is not null
     and v_now > v_show.entry_close_at then
    raise exception 'Entry deadline passed. Scratched entries can no longer be restored.'
      using errcode = '22023';
  end if;

  update public.entries
  set
    status = case when p_is_scratched then 'scratched' else 'entered' end,
    scratched_at = case when p_is_scratched then v_now else null end,
    updated_at = v_now
  where id = v_entry.id;

  v_actor_type := case
    when v_is_service then 'system'
    when v_is_manager then 'secretary'
    else 'exhibitor_portal'
  end;

  insert into public.show_checkin_audit_events(
    show_id, exhibitor_id, event_type, actor_type, actor_user_id, details
  ) values (
    v_entry.show_id,
    v_entry.exhibitor_id,
    case when p_is_scratched then 'entry_scratched' else 'entry_restored' end,
    v_actor_type,
    auth.uid(),
    jsonb_build_object('entry_id', v_entry.id)
  );

  return jsonb_build_object(
    'entry_id', v_entry.id,
    'is_scratched', p_is_scratched,
    'scratched_at', case when p_is_scratched then v_now else null end
  );
end;
$$;

revoke all on function public.set_entry_scratch_state(uuid, boolean) from public;
grant execute on function public.set_entry_scratch_state(uuid, boolean)
  to authenticated, service_role;
