-- Keep privileged reads inside the non-exposed schema; public RPCs are plain
-- invoker wrappers. Authenticated users can execute only these three guarded
-- reads, never the helpers that accept another actor or mutate money/entries.
alter function public.can_refund_show_entries(uuid) set schema entry_refunds_private;
alter function public.get_entry_refund_options(uuid,uuid) set schema entry_refunds_private;
alter function public.get_show_entry_refunds(uuid) set schema entry_refunds_private;
grant usage on schema entry_refunds_private to authenticated;

create function public.can_refund_show_entries(p_show_id uuid)
returns boolean language sql stable security invoker set search_path='' as $$
  select entry_refunds_private.can_refund_show_entries(p_show_id);
$$;
create function public.get_entry_refund_options(p_show_id uuid,p_exhibitor_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select entry_refunds_private.get_entry_refund_options(p_show_id,p_exhibitor_id);
$$;
create function public.get_show_entry_refunds(p_show_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select entry_refunds_private.get_show_entry_refunds(p_show_id);
$$;
revoke all on function public.can_refund_show_entries(uuid),public.get_entry_refund_options(uuid,uuid),
  public.get_show_entry_refunds(uuid) from public,anon;
grant execute on function public.can_refund_show_entries(uuid),public.get_entry_refund_options(uuid,uuid),
  public.get_show_entry_refunds(uuid) to authenticated;
revoke all on entry_refunds_private.requests,entry_refunds_private.entries from public,anon,authenticated;
create policy no_client_refund_rows on entry_refunds_private.requests for all to authenticated using(false) with check(false);
create policy no_client_refund_entries on entry_refunds_private.entries for all to authenticated using(false) with check(false);
