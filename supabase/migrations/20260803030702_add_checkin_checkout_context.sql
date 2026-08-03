-- The public portal never receives cart ownership information. This narrowly
-- scoped function verifies its short-lived check-in session and returns an
-- existing, payable cart only to the server-side checkout function.
create or replace function public.get_exhibitor_checkin_checkout_context(
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_balance public.show_exhibitor_balances%rowtype;
  v_cart public.entry_carts%rowtype;
  v_show public.shows%rowtype;
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now();

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select * into v_show from public.shows where id = v_session.show_id;
  if not found or v_show.payment_timing_mode not in ('online_only', 'online_or_at_show') then
    raise exception 'Online payment is not available for this show';
  end if;

  select b.* into v_balance
  from public.show_exhibitor_balances b
  join public.entry_carts c on c.id = b.entry_cart_id
  where b.show_id = v_session.show_id
    and b.exhibitor_id = v_session.exhibitor_id
    and b.source = 'cart'
    and b.balance_due_cents > 0
    and c.status = 'active'
    and c.payment_status <> 'paid'
  order by b.updated_at desc
  limit 1;

  if not found then
    raise exception 'There is no online payment balance available for this check-in';
  end if;

  select * into v_cart from public.entry_carts where id = v_balance.entry_cart_id;
  if not found or v_cart.user_id is null then
    raise exception 'This payment cart is unavailable';
  end if;

  return jsonb_build_object(
    'cart_id', v_cart.id,
    'user_id', v_cart.user_id,
    'show_id', v_session.show_id,
    'provider', 'stripe'
  );
end;
$$;

revoke all on function public.get_exhibitor_checkin_checkout_context(text)
  from public;
grant execute on function public.get_exhibitor_checkin_checkout_context(text)
  to anon, authenticated, service_role;
