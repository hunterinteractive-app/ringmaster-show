-- Only unsubmitted entries can be corrected here. Existing RLS remains in force.
create or replace function public.edit_entry_cart_item(p_cart_id uuid, p_item_id uuid, p_expected jsonb, p_changes jsonb)
returns void language plpgsql security invoker set search_path='' as $$
declare
 c public.entry_carts%rowtype;
 i public.entry_cart_items%rowtype;
 s public.shows%rowtype;
 b public.breeds%rowtype;
 class_system text;
 new_class text;
begin
 select * into c from public.entry_carts where id=p_cart_id for update;
 if not found or auth.uid() is null then raise exception 'Cart not found' using errcode='42501'; end if;
 if c.status<>'active' or c.active_payment_session_id is not null or c.completed_payment_session_id is not null
   or c.payment_status in ('pending','paid','refunded') or exists(select 1 from public.entries where source_cart_id=c.id) then
   raise exception 'This cart is no longer editable. Cancel an unfinished checkout or use My Entries for submitted entries.';
 end if;
 select * into s from public.shows where id=c.show_id;
 if not found or s.is_locked or s.finalized_at is not null then raise exception 'This show is locked.'; end if;
 if s.entry_close_at is not null and clock_timestamp()>=s.entry_close_at then raise exception 'The entry deadline has passed.'; end if;
 if s.entry_open_at is not null and clock_timestamp()<s.entry_open_at then raise exception 'Entries are not open yet.'; end if;
 select * into i from public.entry_cart_items where id=p_item_id and cart_id=c.id for update;
 if not found or i.is_checkin_fee_carrier or i.is_exhibitor_fee_carrier or i.is_show_addon_carrier then raise exception 'Entry not found'; end if;
 if p_expected is null or jsonb_typeof(p_expected)<>'object' or p_expected='{}'::jsonb
   or not(to_jsonb(i) @> p_expected) then raise exception 'This entry changed. Refresh your cart and try again.'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'object' or exists(
  select 1 from jsonb_object_keys(p_changes) k where k not in ('tattoo','breed','variety','sex','class_name','fur_variety','meat_pen_tattoos')
 ) then raise exception 'Unsupported entry change'; end if;
 if i.meat_pen_id is not null and p_changes ?| array['tattoo','class_name','sex'] then
  raise exception 'Keep the Pen ID and meat pen class; edit the three tattoos instead.';
 end if;
 if i.meat_pen_id is null and p_changes ? 'meat_pen_tattoos' then raise exception 'This entry is not a meat pen.'; end if;
 select * into b from public.breeds where lower(btrim(name))=lower(btrim(coalesce(p_changes->>'breed',i.breed)))
  and species=i.species and is_active and (local_show_id is null or local_show_id=c.show_id)
  order by local_show_id nulls last limit 1;
 if not found then raise exception 'Choose an available breed.'; end if;
 select coalesce(sb.class_system_override::text,b.class_system::text,'four') into class_system
 from (select 1) q left join public.show_breeds sb on sb.show_id=c.show_id and sb.breed_id=b.id;
 new_class:=coalesce(p_changes->>'class_name',i.class_name);
 -- Preserve commercial/fur class types; this editor cannot convert entry types.
 if not coalesce(i.is_fur,false) and i.meat_pen_id is null and
   (p_changes ? 'class_name' or p_changes ? 'breed') then
  if i.class_name not in ('Junior','Intermediate','Senior','Pre-Junior') then
   if new_class is distinct from i.class_name then raise exception 'Keep the commercial entry class.'; end if;
  elsif new_class not in ('Junior','Senior') and not (new_class='Intermediate' and (i.species::text='cavy' or class_system='six'))
    and not (new_class='Pre-Junior' and coalesce(b.has_prejunior,false)) then raise exception 'Choose a valid class for this breed.';
  end if;
 end if;
 if coalesce(i.is_fur,false) and p_changes ? 'class_name' then raise exception 'Keep the Fur/Wool entry class.'; end if;
 if p_changes ? 'fur_variety' and (not coalesce(i.is_fur,false) or coalesce(p_changes->>'fur_variety','') not in ('White','Colored')) then raise exception 'Choose White or Colored for Fur/Wool.'; end if;
 if p_changes ? 'tattoo' and nullif(btrim(p_changes->>'tattoo'),'') is null then raise exception 'Enter a tattoo / ear number.'; end if;
 if p_changes ? 'sex' and lower(coalesce(p_changes->>'sex','')) not in
   (case when i.species::text='cavy' then 'boar' else 'buck' end,case when i.species::text='cavy' then 'sow' else 'doe' end)
 then raise exception 'Choose a valid sex.'; end if;
 update public.entry_cart_items set
  tattoo=case when p_changes ? 'tattoo' then btrim(p_changes->>'tattoo') else tattoo end,
  breed=case when p_changes ? 'breed' then b.name else breed end,
  variety=case when p_changes ? 'variety' then btrim(p_changes->>'variety') else variety end,
  sex=case when p_changes ? 'sex' then p_changes->>'sex' else sex end,
  class_name=new_class,
  fur_variety=case when p_changes ? 'fur_variety' then btrim(p_changes->>'fur_variety') else fur_variety end,
  meat_pen_tattoos=case when p_changes ? 'meat_pen_tattoos' then
    array(select jsonb_array_elements_text(p_changes->'meat_pen_tattoos')) else meat_pen_tattoos end
 where id=i.id and cart_id=c.id;
 -- Recalculate in the same transaction; no payment or submission is initiated.
 perform public.calculate_entry_cart_balance(c.id);
end;
$$;
revoke all on function public.edit_entry_cart_item(uuid,uuid,jsonb,jsonb) from public,anon;
grant execute on function public.edit_entry_cart_item(uuid,uuid,jsonb,jsonb) to authenticated;
