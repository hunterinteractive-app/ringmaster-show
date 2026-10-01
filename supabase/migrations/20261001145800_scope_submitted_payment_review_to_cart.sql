-- Payments on another cart must not disable this unpaid submission.
create or replace function checkout_private.validate_submitted_cart(p_cart_id uuid)
returns void language plpgsql set search_path='' as $$
begin
 -- Known pre-deadline scratches are exempt; ambiguous changes still require review.
 if not exists(select 1 from public.entries where source_cart_id=p_cart_id)
 or exists(select 1 from public.entries e where e.source_cart_id=p_cart_id and
   ((not coalesce(checkout_private.scratch_exempt(e),false) and
     (e.scratched_at is not null or lower(coalesce(e.status,'')) in ('scratched','cancelled','canceled','deleted')))
    or not exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart_id
      and i.id=e.source_cart_item_id and i.exhibitor_id=e.exhibitor_id
      and i.section_id=e.section_id and i.animal_id is not distinct from e.animal_id
      and lower(trim(i.breed))=lower(trim(e.breed))
      and lower(trim(coalesce(i.variety,'')))=lower(trim(coalesce(e.variety,'')))
      and i.tattoo is not distinct from e.tattoo
      and coalesce(i.is_fur,false)=coalesce(e.is_fur,false)
      and (coalesce(i.is_fur,false) or (i.sex is not distinct from e.sex and i.class_name is not distinct from e.class_name)))))
 or exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart_id and
   (i.is_show_addon_carrier or (select count(*) from public.entries e
      where e.source_cart_id=p_cart_id and e.source_cart_item_id=i.id)<>1))
 or exists(select 1 from public.show_exhibitor_balances b where b.entry_cart_id=p_cart_id and b.source='cart'
   and (b.paid_online_cents<>0 or b.paid_manual_cents<>0 or b.refunded_cents<>0)) then
   raise exception 'This submission has changes or prior payments. Please contact the show secretary to confirm the remaining balance.';
 end if;
end;
$$;
revoke all on function checkout_private.validate_submitted_cart(uuid) from public,anon,authenticated;
