-- Reuse the household's active cart for a newly assessed exhibitor fee.
-- Row locking and the existing unique index cover concurrent cart creation.
-- A pending quote or recorded payment must never be changed by this path.
do $migration$
declare
  definition text := pg_get_functiondef('exhibitor_fees_private.ensure_charge(uuid,uuid,uuid,uuid)'::regprocedure);
  old_insert text := $old$    insert into public.entry_carts(user_id,show_id,status,payment_status,currency)
      values(v_user,p_show,'active','unpaid',lower(v_settings.currency)) returning id into v_cart;$old$;
  new_insert text := $new$    select id into v_cart from public.entry_carts
      where show_id=p_show and user_id=v_user and status='active' for update;
    if v_cart is null then
      insert into public.entry_carts(user_id,show_id,status,payment_status,currency)
        values(v_user,p_show,'active','unpaid',lower(v_settings.currency))
        on conflict do nothing returning id into v_cart;
      if v_cart is null then
        select id into v_cart from public.entry_carts
          where show_id=p_show and user_id=v_user and status='active' for update;
      end if;
    end if;
    if v_cart is null or not exists (
      select 1 from public.entry_carts c where c.id=v_cart
        and c.status='active' and c.active_payment_session_id is null
        and c.completed_payment_session_id is null
        and c.payment_status not in ('pending','paid','refunded')
        and lower(c.currency)=lower(v_settings.currency)
        and not exists(select 1 from public.show_exhibitor_balances b
          where b.entry_cart_id=c.id and (b.paid_online_cents<>0
            or b.paid_manual_cents<>0 or b.refunded_cents<>0
            or b.payment_status in ('pending','partial','overpaid','refunded')))
    ) then
      raise exception 'The active cart has a payment in progress or recorded funds. Finish or cancel that checkout before assessing another exhibitor fee.' using errcode='40001';
    end if;$new$;
begin
  if strpos(definition,old_insert)=0 then
    raise exception 'Expected exhibitor fee cart creation was not found; review before applying.';
  end if;
  execute replace(definition,old_insert,new_insert);
end;
$migration$;
