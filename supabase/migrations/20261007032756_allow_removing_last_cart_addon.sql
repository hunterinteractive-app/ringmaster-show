-- Removing the final add-on leaves a valid empty draft. The balance calculator
-- requires at least one item, so clear obsolete balances and skip it when empty.
create or replace function show_addons_private.refresh_cart(p_cart uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  -- Callers have already asserted that this is an unpaid, mutable draft.
  perform set_config('ringmaster.payment_state_write','on',true);
  delete from public.show_exhibitor_balances b where b.entry_cart_id=p_cart and b.source='cart'
    and not exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart and i.exhibitor_id=b.exhibitor_id);
  if exists(select 1 from public.entry_cart_items where cart_id=p_cart) then
    perform public.calculate_entry_cart_balance_internal(p_cart);
  end if;
  perform set_config('ringmaster.payment_state_write','off',true);
end;
$$;
revoke all on function show_addons_private.refresh_cart(uuid) from public,anon,authenticated;
