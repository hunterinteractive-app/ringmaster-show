-- Record staff edits made from Results Entry in the existing correction history.
-- The same permission helper governs both entering results and editing an entry
-- from the results workflow, and locked shows remain immutable.
create or replace function public.record_results_entry_edit(
  p_show_id uuid,
  p_entry_id uuid,
  p_before jsonb,
  p_after jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := 'results_entry';
begin
  if auth.uid() is null
     or not public.user_can_enter_results(p_show_id, auth.uid()) then
    raise exception 'You do not have permission to edit entries from Results Entry.';
  end if;

  if exists (
    select 1
    from public.shows
    where id = p_show_id
      and is_locked = true
  ) then
    raise exception 'This show is locked and entries cannot be edited.';
  end if;

  if not exists (
    select 1
    from public.entries
    where id = p_entry_id
      and show_id = p_show_id
  ) then
    raise exception 'Entry does not belong to this show.';
  end if;

  select ra.role::text
    into v_role
  from public.role_assignments ra
  where ra.show_id = p_show_id
    and ra.user_id = auth.uid()
  order by case ra.role::text
    when 'super_admin' then 1
    when 'admin' then 2
    when 'superintendent' then 3
    when 'reporting_clerk' then 4
    else 5
  end
  limit 1;

  insert into public.entry_correction_audit_log (
    show_id,
    entry_id,
    field_name,
    old_value,
    new_value,
    reason,
    writer_name,
    approved_by_user_id,
    approved_by_role
  ) values (
    p_show_id,
    p_entry_id,
    'results_entry_edit',
    coalesce(p_before, '{}'::jsonb)::text,
    coalesce(p_after, '{}'::jsonb)::text,
    'Edited from Results Entry',
    'Results Entry',
    auth.uid(),
    coalesce(v_role, 'results_entry')
  );
end;
$$;

revoke all on function public.record_results_entry_edit(uuid, uuid, jsonb, jsonb) from public;
grant execute on function public.record_results_entry_edit(uuid, uuid, jsonb, jsonb) to authenticated;
