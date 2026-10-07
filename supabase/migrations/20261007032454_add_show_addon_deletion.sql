-- Remove add-ons from sale without erasing purchased items or receipts.
alter table show_addons_private.offerings
  add column deleted_at timestamptz,
  add column deleted_by uuid,
  add constraint deleted_addon_disabled check (deleted_at is null or (kind='extra' and not enabled));

-- A stale editor must not bring a deleted offering back or alter its history.
create function show_addons_private.guard_deleted_offering()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if old.deleted_at is not null then
    raise exception 'This add-on has been deleted. Reload the add-on list.';
  end if;
  return new;
end;
$$;
revoke all on function show_addons_private.guard_deleted_offering() from public,anon,authenticated;
create trigger guard_deleted_offering before update on show_addons_private.offerings
for each row execute function show_addons_private.guard_deleted_offering();

create function show_addons_private.delete_offering(p_show_id uuid,p_offering_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare o show_addons_private.offerings%rowtype;
begin
  perform show_addons_private.assert_secretary(p_show_id);
  -- Registration and checkout take this same lock, so deleting cannot race a new order.
  select * into o from show_addons_private.offerings
    where id=p_offering_id and show_id=p_show_id for update;
  if not found then raise exception 'Add-on not found.'; end if;
  if o.kind<>'extra' then raise exception 'Only show add-ons can be deleted here.'; end if;
  if o.deleted_at is not null then return; end if;
  update show_addons_private.offerings
    set enabled=false,deleted_at=now(),deleted_by=auth.uid(),updated_at=now()
    where id=o.id;
  -- Selections, balances, and payment records deliberately remain intact.
end;
$$;
revoke all on function show_addons_private.delete_offering(uuid,uuid) from public,anon;
grant execute on function show_addons_private.delete_offering(uuid,uuid) to authenticated,service_role;

create function public.delete_show_addon(p_show_id uuid,p_offering_id uuid)
returns void language sql security invoker set search_path='' as $$
  select show_addons_private.delete_offering(p_show_id,p_offering_id);
$$;
revoke all on function public.delete_show_addon(uuid,uuid) from public,anon;
grant execute on function public.delete_show_addon(uuid,uuid) to authenticated,service_role;

create or replace function show_addons_private.catalog(p_show_id uuid,p_admin boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.shows%rowtype; items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in to view contests and add-ons.' using errcode='42501'; end if;
  select * into s from public.shows where id=p_show_id;
  if not found or (not coalesce(s.is_published,false) and not public.user_can_manage_show_settings(p_show_id)) then raise exception 'Show is unavailable.' using errcode='42501'; end if;
  if p_admin and not public.user_can_manage_show_settings(p_show_id) then raise exception 'Show secretary permission is required.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object(
      'effective_open_at',case when o.use_show_entry_dates then s.entry_open_at else o.registration_open_at end,
      'effective_close_at',case when o.use_show_entry_dates then s.entry_close_at else o.registration_close_at end,
      'effective_age_date',case coalesce(o.contest_config->>'age_as_of','show_start') when 'custom' then (o.contest_config->>'age_date')::date when 'show_end' then s.end_date else s.start_date end,
      'registration_status',case when o.results_published_at is not null then 'closed' when coalesce(s.is_locked,false) or s.finalized_at is not null then 'locked'
        when (case when o.use_show_entry_dates then s.entry_open_at else o.registration_open_at end)>now() then 'upcoming'
        when (case when o.use_show_entry_dates then s.entry_close_at else o.registration_close_at end)<now() then 'closed'
        else 'open' end) order by lower(o.name),o.id),'[]') into items from show_addons_private.offerings o
    where o.show_id=p_show_id and o.deleted_at is null and (p_admin or (o.enabled and case when o.kind='contest' then s.contests_enabled else s.extras_enabled end));
  return jsonb_build_object('contests_enabled',s.contests_enabled,'extras_enabled',s.extras_enabled,'items',items,
    'currency',coalesce((select lower(currency) from public.show_fee_settings where show_id=p_show_id),'usd'),
    'entry_open_at',s.entry_open_at,'entry_close_at',s.entry_close_at,'locked',coalesce(s.is_locked,false) or s.finalized_at is not null);
end;
$$;
