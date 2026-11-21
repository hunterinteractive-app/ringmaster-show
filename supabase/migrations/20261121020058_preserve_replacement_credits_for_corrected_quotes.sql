create or replace function show_finances_private.replacement_offsets(
 p_show uuid,p_exhibitor uuid,p_manual_discount integer,p_manual_subtotal integer)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 v_enabled timestamptz; old_entry record; new_entry record;
 v_used uuid[]:='{}'; v_pairs jsonb:='[]'; v_amount integer;
begin
 select enabled_at into v_enabled from show_finances_private.replacement_policy where singleton;
 -- Only an unambiguous, fully paid, unrefunded original checkout is eligible.
 -- Reassigned or partially refunded carts continue through financial review;
 -- never guess which entry owns the remaining payment.
 for old_entry in
  select e.*, b.id balance_id,
   atom.cents-atom.discount available_cents
  from public.entries e
  join public.entry_cart_items i on i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id
   and i.exhibitor_id=e.exhibitor_id and i.section_id=e.section_id
   and coalesce(i.is_fur,false)=coalesce(e.is_fur,false)
  join public.show_exhibitor_balances b on b.source='cart' and b.show_id=e.show_id
   and b.exhibitor_id=e.exhibitor_id and coalesce(b.entry_cart_id,b.cart_id)=e.source_cart_id
  join public.entry_carts c on c.id=e.source_cart_id and c.status='submitted'
  cross join lateral jsonb_array_elements(b.section_breakdown) s
  cross join lateral (select coalesce(sum((x->>'entries_subtotal_cents')::integer)
   filter(where coalesce((x->>'discount_scope_eligible')::boolean,true)),0) cents
   from jsonb_array_elements(b.section_breakdown) x) eligible
  cross join lateral (
   -- Use the same cumulative cent allocation as payment reassignment; a
   -- discount that does not divide evenly must not lose a cent per animal.
   with items as (
    select ci.*,row_number() over(partition by ci.section_id,coalesce(ci.is_fur,false) order by ci.id) rn,
     count(*) over(partition by ci.section_id,coalesce(ci.is_fur,false)) cnt
    from public.entry_cart_items ci where ci.cart_id=e.source_cart_id and ci.exhibitor_id=p_exhibitor
     -- A reviewed correction keeps the original items for audit; only items in
     -- its replacement quote were charged and can fund a replacement offset.
     and (not exists(select 1 from show_finances_private.cart_quote_corrections qc where qc.balance_id=b.id)
      or exists(select 1 from show_finances_private.cart_quote_corrections qc
       cross join lateral jsonb_array_elements(qc.quote_items) qi
       where qc.balance_id=b.id and qi->>'id'=ci.id::text))
     and not coalesce(ci.is_show_addon_carrier,false) and not coalesce(ci.is_checkin_fee_carrier,false)
     and not coalesce(ci.is_exhibitor_fee_carrier,false)
   ), amounts as (
    select ci.id,show_finances_private.share(
     coalesce((sb->>case when coalesce(ci.is_fur,false) then 'fur_subtotal_cents' else 'entries_subtotal_cents' end)::integer,0),
     ci.rn-1,1,ci.cnt) cents,
     not coalesce(ci.is_fur,false) and coalesce((sb->>'discount_scope_eligible')::boolean,true) eligible
    from items ci join jsonb_array_elements(b.section_breakdown) sb on sb->>'section_id'=ci.section_id::text
   ), net as (
    select id,cents,show_finances_private.share(coalesce(b.discount_cents,0),
     coalesce(sum(case when eligible then cents else 0 end) over(order by id rows between unbounded preceding and 1 preceding),0)::bigint,
     case when eligible then cents else 0 end,eligible.cents) discount
    from amounts
   ) select * from net where id=e.source_cart_item_id
  ) atom
  where e.show_id=p_show and e.exhibitor_id=p_exhibitor
   and e.scratched_at>=v_enabled and lower(coalesce(e.status,'')) not in ('deleted','cancelled','canceled')
   and not coalesce(e.is_test,false) and not coalesce(e.is_commercial,false)
   and e.species is not null and e.created_at is not null
   and s->>'section_id'=e.section_id::text
   and b.calculated_total_cents>0
   and coalesce(b.paid_online_cents,0)+coalesce(b.paid_manual_cents,0)>=b.calculated_total_cents
   and coalesce(b.refunded_cents,0)=0
   and coalesce((b.fee_snapshot->>'entry_refund_credit_cents')::integer,0)=0
   and coalesce(b.discount_cents,0)<=eligible.cents
   and not exists(select 1 from public.entries moved join public.entry_cart_items mi on mi.id=moved.source_cart_item_id
    where moved.source_cart_id=e.source_cart_id and
     (moved.exhibitor_id is distinct from mi.exhibitor_id or moved.section_id is distinct from mi.section_id))
   -- Require exact source item counts; malformed legacy checkout data fails closed.
   and (s->>case when coalesce(e.is_fur,false) then 'fur_count' else 'entry_count' end)::integer=
    (select count(*) from public.entry_cart_items ci where ci.cart_id=e.source_cart_id
     and ci.exhibitor_id=e.exhibitor_id and ci.section_id=e.section_id
     -- A reviewed correction keeps the original items for audit; only items in
     -- its replacement quote were charged and can fund a replacement offset.
     and (not exists(select 1 from show_finances_private.cart_quote_corrections qc where qc.balance_id=b.id)
      or exists(select 1 from show_finances_private.cart_quote_corrections qc
       cross join lateral jsonb_array_elements(qc.quote_items) qi
       where qc.balance_id=b.id and qi->>'id'=ci.id::text))
     and coalesce(ci.is_fur,false)=coalesce(e.is_fur,false)
     and not coalesce(ci.is_show_addon_carrier,false) and not coalesce(ci.is_checkin_fee_carrier,false)
     and not coalesce(ci.is_exhibitor_fee_carrier,false))
   and (select count(*) from public.entries duplicate where duplicate.source_cart_item_id=e.source_cart_item_id)=1
  order by e.scratched_at,e.id
 loop
  if coalesce(old_entry.available_cents,0)<=0 then continue; end if;
  select e.id,e.tattoo,
   case when coalesce(e.is_fur,false) then round(coalesce(sf.fur_fee,0)*100)::integer
    else price.cents-show_finances_private.share(p_manual_discount,price.before,price.cents,p_manual_subtotal) end cents
  into new_entry
  from public.entries e join public.show_section_fee_settings sf on sf.section_id=e.section_id
  left join lateral (
   select * from (
    select me.id,round(coalesce(mf.fee_per_entry,0)*100)::integer cents,
     coalesce(sum(round(coalesce(mf.fee_per_entry,0)*100)) over(order by me.id rows between unbounded preceding and 1 preceding),0)::bigint before
    from public.entries me join public.show_sections ms on ms.id=me.section_id and ms.show_id=me.show_id
    left join public.show_section_fee_settings mf on mf.section_id=me.section_id
    where me.show_id=p_show and me.exhibitor_id=p_exhibitor and me.source_cart_id is null
     and me.scratched_at is null and not coalesce(me.is_test,false) and not coalesce(me.is_fur,false)
     and lower(coalesce(me.status,'')) not in ('deleted','cancelled','canceled','scratched')
   ) amounts where id=e.id
  ) price on true
  where e.show_id=p_show and e.exhibitor_id=p_exhibitor and e.section_id=old_entry.section_id
   and e.source_cart_id is null and e.source_cart_item_id is null
   and e.created_at>=v_enabled and e.created_at>old_entry.created_at
   -- Accept add-then-scratch during the same editing session as well as later additions.
   and e.created_at>=old_entry.scratched_at-interval '15 minutes'
   and e.scratched_at is null and lower(coalesce(e.status,'')) not in ('deleted','cancelled','canceled','scratched')
   and not coalesce(e.is_test,false) and not coalesce(e.is_commercial,false)
   and lower(e.species::text)=lower(old_entry.species::text)
   and coalesce(e.is_fur,false)=coalesce(old_entry.is_fur,false)
   and not(e.id=any(v_used))
  order by e.created_at,e.id limit 1;
  if not found then continue; end if;
  v_amount:=least(old_entry.available_cents,greatest(0,new_entry.cents));
  if v_amount<=0 then continue; end if;
  v_used:=array_append(v_used,new_entry.id);
  v_pairs:=v_pairs||jsonb_build_array(jsonb_build_object('scratched_entry_id',old_entry.id,
   'replacement_entry_id',new_entry.id,'section_id',old_entry.section_id,'source_balance_id',old_entry.balance_id,
   'scratched_tattoo',old_entry.tattoo,'replacement_tattoo',new_entry.tattoo,'amount_cents',v_amount));
 end loop;
 return v_pairs;
end $$;
revoke all on function show_finances_private.replacement_offsets(uuid,uuid,integer,integer) from public,anon,authenticated;

