create or replace function public.search_show_checkin_exhibitors(
  p_show_id uuid,
  p_search text default ''
)
returns table (
  exhibitor_id uuid,
  exhibitor_name text,
  exhibitor_number text,
  checkin_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in.' using errcode = '42501';
  end if;

  return query
  select
    e.exhibitor_id,
    coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, ''))),
    x.exhibitor_number::text,
    r.status
  from public.entries e
  join public.exhibitors x on x.id = e.exhibitor_id
  left join public.show_checkin_records r
    on r.show_id = p_show_id and r.exhibitor_id = e.exhibitor_id
  where e.show_id = p_show_id
    and (
      v_search = ''
      or lower(coalesce(x.display_name, '') || ' ' || coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '') || ' ' || coalesce(x.exhibitor_number::text, '')) like '%' || v_search || '%'
    )
  group by e.exhibitor_id, x.display_name, x.first_name, x.last_name, x.exhibitor_number, r.status
  order by coalesce(nullif(x.display_name, ''), trim(coalesce(x.first_name, '') || ' ' || coalesce(x.last_name, '')))
  limit 40;
end;
$$;

create or replace function public.complete_exhibitor_checkin_by_secretary(
  p_show_id uuid,
  p_exhibitor_id uuid,
  p_entries_confirmed boolean,
  p_initials text default null,
  p_signature_data text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.show_checkin_records%rowtype;
  v_now timestamptz := now();
  v_initials text := nullif(btrim(coalesce(p_initials, '')), '');
  v_signature text := nullif(btrim(coalesce(p_signature_data, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s check-in.' using errcode = '42501';
  end if;
  if not p_entries_confirmed then
    raise exception 'Confirm the exhibitor''s entries before completing check-in.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.entries
    where show_id = p_show_id and exhibitor_id = p_exhibitor_id
  ) then
    raise exception 'This exhibitor does not have entries in this show.' using errcode = '22023';
  end if;

  insert into public.show_checkin_records (show_id, exhibitor_id, status)
  values (p_show_id, p_exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id) do nothing;

  select * into v_record from public.show_checkin_records
  where show_id = p_show_id and exhibitor_id = p_exhibitor_id
  for update;
  if v_record.status = 'locked' then
    raise exception 'This check-in has been locked.' using errcode = '22023';
  end if;

  update public.show_checkin_records
  set status = 'completed', confirmed_at = v_now,
      confirmed_by_type = 'secretary', confirmed_by_user_id = auth.uid(),
      confirmation_initials = v_initials, signature_data = v_signature,
      receipt_preference = 'no_receipt', completed_at = v_now, updated_at = v_now
  where id = v_record.id;

  insert into public.show_checkin_audit_events (
    show_id, exhibitor_id, checkin_record_id, event_type, actor_type, actor_user_id, details
  ) values (
    p_show_id, p_exhibitor_id, v_record.id, 'checkin_completed_by_secretary', 'secretary', auth.uid(),
    jsonb_build_object('note', v_note, 'has_initials', v_initials is not null, 'has_signature', v_signature is not null)
  );

  return jsonb_build_object('status', 'completed', 'completed_at', v_now, 'completed_by', 'secretary');
end;
$$;

revoke all on function public.search_show_checkin_exhibitors(uuid, text) from public, anon;
grant execute on function public.search_show_checkin_exhibitors(uuid, text) to authenticated, service_role;
revoke all on function public.complete_exhibitor_checkin_by_secretary(uuid, uuid, boolean, text, text, text) from public, anon;
grant execute on function public.complete_exhibitor_checkin_by_secretary(uuid, uuid, boolean, text, text, text) to authenticated, service_role;
