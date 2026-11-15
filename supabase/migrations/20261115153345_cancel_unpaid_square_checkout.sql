-- The backend calls this only after Square confirms the exact order CANCELED
-- with no payment tenders. Never expose the local unlock directly to clients.
create function checkout_private.finish_cancelled_square_checkout(p_cart_id uuid, p_payment_session_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; s public.show_payment_sessions%rowtype;
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'Backend authorization required' using errcode='42501';
  end if;
  select * into c from public.entry_carts where id=p_cart_id for update;
  select * into s from public.show_payment_sessions where id=p_payment_session_id and cart_id=p_cart_id for update;
  if c.id is null or s.id is null or s.provider<>'square' then raise exception 'Square checkout not found.'; end if;
  if c.status<>'active' or c.completed_payment_session_id is not null or c.payment_status in ('paid','refunded')
    or s.attempt_status='finalized' or s.provider_payment_id is not null
    or exists(select 1 from public.show_exhibitor_balances where entry_cart_id=c.id
      and (paid_online_cents<>0 or paid_manual_cents<>0 or refunded_cents<>0)) then
    raise exception 'This cart has a payment and cannot be reopened.';
  end if;
  if c.active_payment_session_id is distinct from s.id then
    if c.active_payment_session_id is null and s.attempt_status='cancelled'
      and s.failure_code='buyer_cancelled_checkout' then
      return jsonb_build_object('cancelled',true,'already_cancelled',true);
    end if;
    raise exception 'The checkout changed. Refresh your cart and try again.';
  end if;
  perform public.mark_payment_attempt_terminal(s.id,'square','cancelled','buyer_cancelled_checkout',
    'The exhibitor canceled the unpaid Square checkout to edit their cart.',null);
  update public.show_payment_sessions set metadata=coalesce(metadata,'{}'::jsonb)||
    jsonb_build_object('provider_link_deactivated',true,'cancelled_for_cart_edit_at',now()) where id=s.id;
  -- Recompute from the remaining items, including carts edited by older clients
  -- while the now-canceled payment quote was frozen.
  perform show_addons_private.refresh_cart(c.id);
  return jsonb_build_object('cancelled',true,'already_cancelled',false);
end;
$$;
revoke all on function checkout_private.finish_cancelled_square_checkout(uuid,uuid) from public,anon,authenticated;
grant usage on schema checkout_private to service_role;
grant execute on function checkout_private.finish_cancelled_square_checkout(uuid,uuid) to service_role;
create function public.finish_cancelled_square_checkout(p_cart_id uuid,p_payment_session_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select checkout_private.finish_cancelled_square_checkout(p_cart_id,p_payment_session_id);
$$;
revoke all on function public.finish_cancelled_square_checkout(uuid,uuid) from public,anon,authenticated;
grant execute on function public.finish_cancelled_square_checkout(uuid,uuid) to service_role;

-- Animal entries must obey the same in-flight checkout lock as add-ons.
create or replace function checkout_private.serialize_cart_edit()
returns trigger language plpgsql security definer set search_path='' as $$
declare c record;
begin
  for c in select id,status,completed_payment_session_id,active_payment_session_id,payment_status
    from public.entry_carts
    where id in (case when tg_op<>'INSERT' then old.cart_id end,
                 case when tg_op<>'DELETE' then new.cart_id end)
    order by id for update
  loop
    if c.completed_payment_session_id is not null then
      raise exception 'This cart has already been paid. Start a new cart for additional entries.';
    end if;
    if c.active_payment_session_id is not null or c.payment_status='pending' then
      raise exception 'Cancel the unfinished checkout before changing cart items.';
    end if;
  end loop;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
