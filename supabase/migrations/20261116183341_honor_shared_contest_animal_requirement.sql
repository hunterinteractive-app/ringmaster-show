-- Sharing a contest must preserve its configured animal-entry requirement.
-- Judging may be entered without an animal; Costume/Showmanship still require
-- an eligible youth animal when their requires_animal_entry flag is enabled.
CREATE OR REPLACE FUNCTION show_addons_private.assert_eligible(p_cart entry_carts, p_offer show_addons_private.offerings, p_ex uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.shows%rowtype; opens timestamptz; closes timestamptz;
begin
  select * into s from public.shows where id=p_offer.show_id;
  if not show_addons_private.offering_accepts_show(p_offer.id,p_cart.show_id) or p_offer.deleted_at is not null or not p_offer.enabled or not (case when p_offer.kind='contest' then s.contests_enabled else s.extras_enabled end)
    or not coalesce(s.is_published,false) then raise exception 'This contest or add-on is not available.'; end if;
  if exists(select 1 from public.shows src where src.id=p_cart.show_id and (not coalesce(src.is_published,false) or coalesce(src.is_locked,false) or src.finalized_at is not null)) then raise exception 'The entry show is unavailable or locked.'; end if;
  if coalesce(s.is_locked,false) or s.finalized_at is not null then raise exception 'This show is locked or finalized.'; end if;
  opens:=case when p_offer.use_show_entry_dates then s.entry_open_at else p_offer.registration_open_at end;
  closes:=case when p_offer.use_show_entry_dates then s.entry_close_at else p_offer.registration_close_at end;
  if opens>now() or closes<now() then raise exception 'Registration is outside the registration window for %.',p_offer.name; end if;
  if not exists(select 1 from public.exhibitors e where e.id=p_ex and e.owner_user_id=p_cart.user_id and e.is_active) then
    raise exception 'Choose an active exhibitor from this household.' using errcode='42501'; end if;
  if exists(select 1 from show_addons_private.contest_show_links where offering_id=p_offer.id) then
    if p_offer.requires_animal_entry and jsonb_array_length(show_addons_private.offering_animals(p_cart,p_ex,p_offer.id))=0 then
      raise exception '% requires a youth animal entry in the rabbit or linked cavy show for this exhibitor.',p_offer.name;
    end if;
    return;
  end if;
  if p_offer.requires_animal_entry and not (
    exists(select 1 from public.entries e where e.show_id=s.id and e.exhibitor_id=p_ex and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled','withdrawn'))
    or exists(select 1 from public.entry_cart_items i where i.cart_id=p_cart.id and i.exhibitor_id=p_ex and not i.is_checkin_fee_carrier and not coalesce(i.is_fur,false))) then
    raise exception '% requires an animal entry for this exhibitor in this show.',p_offer.name;
  end if;
end;
$function$;
