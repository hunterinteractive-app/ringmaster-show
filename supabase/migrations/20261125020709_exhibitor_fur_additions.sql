-- Existing entries may purchase fur-only additions through normal checkout.
-- No submitted carts, payments, or existing entries are modified.
create schema if not exists fur_additions_private;
revoke all on schema fur_additions_private from public, anon;
grant usage on schema fur_additions_private to authenticated;

create function fur_additions_private.manage(p_entry_id uuid,
 p_section_ids uuid[] default null, p_fur_variety text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 e public.entries; s public.shows; c public.entry_carts;
 v_owner uuid; v_sections jsonb; v_option jsonb; v_parent public.entries;
 v_section uuid; v_count integer:=0; v_currency text;
begin
 select * into e from public.entries where id=p_entry_id;
 select owner_user_id into v_owner from public.exhibitors where id=e.exhibitor_id and is_active;
 if auth.uid() is null or e.id is null or v_owner is null
  or not coalesce(household_private.has_access(v_owner),false) then
  raise exception 'You do not have access to this entry.' using errcode='42501';
 end if;
 select * into s from public.shows where id=e.show_id;
 if coalesce(s.is_locked,false) or s.finalized_at is not null
  or not coalesce(s.is_published,false) or s.entry_open_at>now() or s.entry_close_at<=now() then
  raise exception 'Fur/Wool can only be added while entries are open.';
 end if;
 if coalesce(e.is_fur,false) or lower(e.species::text)<>'rabbit' or e.meat_pen_id is not null
  or lower(coalesce(e.status,'')) in ('scratched','removed','cancelled','canceled','withdrawn') then
  raise exception 'Choose an active rabbit class entry.';
 end if;
 if e.animal_id is null and nullif(btrim(e.tattoo),'') is null then
  raise exception 'This entry needs an animal or tattoo before adding Fur/Wool.';
 end if;
 if p_section_ids is not null then
  if cardinality(p_section_ids)=0 or cardinality(p_section_ids)>100
    or array_position(p_section_ids,null) is not null then raise exception 'Select at least one show section.'; end if;
  if p_fur_variety is null or p_fur_variety not in ('White','Colored') then
    raise exception 'Choose White or Colored for the Fur/Wool class.';
  end if;
  -- Serialize requests from multiple tabs/household members, then use the same
  -- cart row lock as checkout quote creation and payment finalization.
  perform pg_advisory_xact_lock(hashtextextended('fur-addition:'||e.show_id::text||':'||v_owner::text,0));
  select * into c from public.entry_carts where show_id=e.show_id and user_id=v_owner and status='active' for update;
  if c.id is null then
   insert into public.entry_carts(show_id,user_id) values(e.show_id,v_owner)
    on conflict(show_id,user_id) where status='active' do nothing;
   select * into c from public.entry_carts where show_id=e.show_id and user_id=v_owner and status='active' for update;
  end if;
  perform show_addons_private.assert_cart(c.id,true);
 end if;
 select coalesce(currency,'USD') into v_currency from public.show_fee_settings where show_id=e.show_id;
 with parents as (
  select distinct on (p.section_id) p.* from public.entries p
  where p.show_id=e.show_id and p.exhibitor_id=e.exhibitor_id and not coalesce(p.is_fur,false)
   and lower(p.species::text)='rabbit' and p.meat_pen_id is null
   and lower(coalesce(p.status,'')) not in ('scratched','removed','cancelled','canceled','withdrawn')
   and (case when e.animal_id is not null then p.animal_id=e.animal_id
    else p.animal_id is null and upper(btrim(p.tattoo))=upper(btrim(e.tattoo)) and p.breed=e.breed end)
  order by p.section_id,p.id
 ), choices as (
  select p.id as entry_id, ss.id, coalesce(nullif(ss.display_name,''),initcap(ss.kind::text)||' '||ss.letter) label,
   round(f.fur_fee*100)::integer fee_cents, ss.sort_order, ss.kind,ss.letter,
   case when exists(select 1 from public.entries x where x.show_id=p.show_id and x.section_id=p.section_id
    and x.exhibitor_id=p.exhibitor_id and coalesce(x.is_fur,false)
    and (case when p.animal_id is not null then x.animal_id=p.animal_id
     else x.animal_id is null and upper(btrim(x.tattoo))=upper(btrim(p.tattoo)) and x.breed=p.breed end))
    then 'Already entered in Fur/Wool'
   when exists(select 1 from public.entry_cart_items i join public.entry_carts cart on cart.id=i.cart_id
    where cart.show_id=p.show_id and cart.status='active' and i.section_id=p.section_id
     and i.exhibitor_id=p.exhibitor_id and coalesce(i.is_fur,false)
     and (case when p.animal_id is not null then i.animal_id=p.animal_id
      else i.animal_id is null and upper(btrim(i.tattoo))=upper(btrim(p.tattoo)) and i.breed=p.breed end))
    then 'Already in cart' else null end unavailable_reason
  from parents p join public.show_sections ss on ss.id=p.section_id and ss.show_id=p.show_id
   join public.show_section_fee_settings f on f.section_id=ss.id
  where coalesce(ss.is_enabled,true) and f.fur_fee>0
 ) select coalesce(jsonb_agg(to_jsonb(choices) order by kind,sort_order,letter,id),'[]') into v_sections from choices;
 if p_section_ids is null then
  select * into c from public.entry_carts where show_id=e.show_id and user_id=v_owner and status='active';
  return jsonb_build_object('show_id',s.id,'show_name',s.name,'tattoo',e.tattoo,
   'currency',coalesce(v_currency,'USD'),'sections',v_sections,'cart_id',c.id);
 end if;
 for v_section in select distinct unnest(p_section_ids) order by 1 loop
  select value into v_option from jsonb_array_elements(v_sections) where value->>'id'=v_section::text;
  if v_option is null then raise exception 'A selected section is not eligible for this rabbit.'; end if;
  if v_option->>'unavailable_reason'='Already in cart' then continue; end if;
  if v_option->>'unavailable_reason' is not null then raise exception '%: %',v_option->>'label',v_option->>'unavailable_reason'; end if;
  select * into v_parent from public.entries where id=(v_option->>'entry_id')::uuid for share;
  -- Recheck after acquiring the parent lock (a scratch may race the picker).
  if lower(coalesce(v_parent.status,'')) in ('scratched','removed','cancelled','canceled','withdrawn') then
   raise exception 'The class entry changed. Refresh your entries and try again.';
  end if;
  insert into public.entry_cart_items(cart_id,section_id,animal_id,exhibitor_id,species,
    tattoo,animal_name,breed,variety,fur_variety,sex,class_name,is_fur)
   values(c.id,v_section,v_parent.animal_id,v_parent.exhibitor_id,v_parent.species,
    v_parent.tattoo,v_parent.animal_name,v_parent.breed,p_fur_variety,p_fur_variety,
    v_parent.sex,v_parent.class_name,true);
  v_count:=v_count+1;
 end loop;
 perform public.calculate_entry_cart_balance_internal(c.id);
 return jsonb_build_object('cart_id',c.id,'show_id',s.id,'show_name',s.name,'added_count',v_count);
end $$;
revoke all on function fur_additions_private.manage(uuid,uuid[],text) from public,anon;
grant execute on function fur_additions_private.manage(uuid,uuid[],text) to authenticated;
create function public.exhibitor_fur_additions(p_entry_id uuid,
 p_section_ids uuid[] default null,p_fur_variety text default null)
returns jsonb language sql security invoker set search_path='' as $$
 select fur_additions_private.manage(p_entry_id,p_section_ids,p_fur_variety);
$$;
revoke all on function public.exhibitor_fur_additions(uuid,uuid[],text) from public,anon;
grant execute on function public.exhibitor_fur_additions(uuid,uuid[],text) to authenticated;

-- A fur-only cart must not collect the section's regular flat entry fee again.
-- Mixed carts retain their existing fee from the regular class-entry line.
do $$
declare d text; old_clause text:='when ci.is_exhibitor_fee_carrier then 0 else coalesce(sffs.fee_per_show, 0)';
begin
 d:=pg_get_functiondef('public.calculate_entry_cart_balance_without_canada_special(uuid)'::regprocedure);
 if strpos(d,old_clause)=0 then raise exception 'Section flat-fee calculation anchor changed'; end if;
 execute replace(d,old_clause,'when ci.is_exhibitor_fee_carrier or coalesce(ci.is_fur,false) then 0 else coalesce(sffs.fee_per_show, 0)');
end $$;
