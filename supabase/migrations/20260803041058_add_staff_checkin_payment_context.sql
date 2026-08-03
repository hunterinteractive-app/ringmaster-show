create or replace function public.get_show_checkin_payment_context(
  p_show_id uuid,
  p_exhibitor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_due integer;
  v_currency text;
begin
  if not public.user_can_manage_entries(p_show_id)
     and not public.user_can_manage_show_settings(p_show_id) then
    raise exception 'You do not have permission to manage this show''s payments.' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.entries where show_id = p_show_id and exhibitor_id = p_exhibitor_id
  ) then
    raise exception 'This exhibitor does not have entries in this show.' using errcode = '22023';
  end if;

  select coalesce(sum(balance_due_cents), 0)::integer, min(lower(currency))
  into v_due, v_currency
  from public.show_exhibitor_balances
  where show_id = p_show_id and exhibitor_id = p_exhibitor_id;

  return jsonb_build_object(
    'balance_due_cents', greatest(coalesce(v_due, 0), 0),
    'currency', coalesce(v_currency, 'usd')
  );
end;
$$;

revoke all on function public.get_show_checkin_payment_context(uuid, uuid) from public, anon;
grant execute on function public.get_show_checkin_payment_context(uuid, uuid) to authenticated, service_role;
