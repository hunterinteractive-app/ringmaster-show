create or replace function public.get_show_checkin_dashboard(p_show_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_records jsonb;
  v_recent jsonb;
  v_pending_changes integer;
  v_unpaid_exhibitors integer;
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to view this show''s check-in dashboard.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'not_started', count(*) filter (where status = 'not_started'),
    'in_progress', count(*) filter (where status = 'in_progress'),
    'completed', count(*) filter (where status = 'completed'),
    'reviewed', count(*) filter (where status = 'reviewed_by_secretary'),
    'locked', count(*) filter (where status = 'locked')
  ) into v_records
  from public.show_checkin_records
  where show_id = p_show_id;

  select count(*) into v_pending_changes
  from public.show_checkin_change_requests
  where show_id = p_show_id and status in ('submitted', 'pending_payment', 'pending_review');

  select count(distinct exhibitor_id) into v_unpaid_exhibitors
  from public.show_exhibitor_balances
  where show_id = p_show_id and coalesce(balance_due_cents, 0) > 0;

  select coalesce(jsonb_agg(item order by completed_at desc), '[]'::jsonb) into v_recent
  from (
    select jsonb_build_object(
      'id', r.id,
      'status', r.status,
      'completed_at', r.completed_at,
      'receipt_sent_at', r.receipt_sent_at,
      'receipt_preference', r.receipt_preference,
      'exhibitor_name', coalesce(nullif(e.display_name, ''), trim(coalesce(e.first_name, '') || ' ' || coalesce(e.last_name, ''))),
      'exhibitor_number', e.exhibitor_number
    ) as item, r.completed_at
    from public.show_checkin_records r
    join public.exhibitors e on e.id = r.exhibitor_id
    where r.show_id = p_show_id and r.status in ('completed', 'reviewed_by_secretary', 'locked')
    order by r.completed_at desc nulls last
    limit 20
  ) recent;

  return jsonb_build_object(
    'records', coalesce(v_records, '{}'::jsonb),
    'pending_change_requests', coalesce(v_pending_changes, 0),
    'unpaid_exhibitors', coalesce(v_unpaid_exhibitors, 0),
    'recent_checkins', v_recent
  );
end;
$$;

revoke all on function public.get_show_checkin_dashboard(uuid) from public, anon;
grant execute on function public.get_show_checkin_dashboard(uuid) to authenticated, service_role;
