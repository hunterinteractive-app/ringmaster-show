-- A pen is one entry, regardless of its three tattoos. Limits are per exhibitor,
-- across all sections and carts of the configured show, not per household.
create table meat_pens_private.entry_limits (
 show_id uuid primary key references public.shows(id) on delete cascade,
 maximum integer not null check (maximum > 0)
);
alter table meat_pens_private.entry_limits enable row level security;
revoke all on table meat_pens_private.entry_limits from public,anon,authenticated;
insert into meat_pens_private.entry_limits(show_id,maximum)
select id,2 from public.shows
where owner_user_id='bca983ed-59ac-4615-a9a7-a2ce56d3d8e8'
 and club_id='48522136-118e-4860-aa46-1abb2d783809'
 and name='Houston Livestock Show and Rodeo - Youth Meat Pen Show';

create function meat_pens_private.is_pen(p_class text,p_species text,p_fur boolean)
returns boolean language sql immutable set search_path='' as $$
 select lower(btrim(coalesce(p_class,''))) in ('meat pen','meat pens','meat_pen')
  and p_species='rabbit' and not coalesce(p_fur,false);
$$;

-- Caller holds the exhibitor/show advisory lock. Volatile reads take a fresh
-- snapshot after waiting for another checkout, including within row triggers.
create function meat_pens_private.used_places(p_show uuid,p_exhibitor uuid,
 p_cart uuid default null,p_entry uuid default null,p_item uuid default null)
returns bigint language sql volatile security definer set search_path='' as $$
 select
 (select count(*) from public.entries e
  where e.show_id=p_show and e.exhibitor_id=p_exhibitor and e.id is distinct from p_entry
   and meat_pens_private.is_pen(e.class_name,e.species::text,e.is_fur)
   and e.scratched_at is null and lower(coalesce(e.status,'')) not in ('scratched','removed','cancelled'))
 +
 (select count(*) from public.entry_cart_items i join public.entry_carts c on c.id=i.cart_id
  where c.show_id=p_show and i.exhibitor_id=p_exhibitor and i.id is distinct from p_item
   and c.status='active'
   and (c.id=p_cart or c.active_payment_session_id is not null or c.payment_status='pending')
   and not i.is_checkin_fee_carrier and not i.is_exhibitor_fee_carrier and not i.is_show_addon_carrier
   and meat_pens_private.is_pen(i.class_name,i.species::text,i.is_fur)
   -- During finalization a pen exists in both tables. Count it only once.
   and not exists(select 1 from public.entries e where e.source_cart_item_id=i.id and not e.is_fur));
$$;

create function meat_pens_private.enforce_entry_limit() returns trigger
language plpgsql security definer set search_path='' as $$
declare sid uuid; cid uuid; item_id uuid; entry_id uuid; cap integer;
begin
 if not meat_pens_private.is_pen(new.class_name,new.species::text,new.is_fur) then return new; end if;
 if tg_table_name='entry_cart_items' then
  if new.is_checkin_fee_carrier or new.is_exhibitor_fee_carrier or new.is_show_addon_carrier then return new; end if;
  select show_id into sid from public.entry_carts where id=new.cart_id;
  cid:=new.cart_id; item_id:=new.id;
  if tg_op='UPDATE' and old.cart_id=new.cart_id and old.exhibitor_id=new.exhibitor_id
    and meat_pens_private.is_pen(old.class_name,old.species::text,old.is_fur)
    and not old.is_checkin_fee_carrier and not old.is_exhibitor_fee_carrier and not old.is_show_addon_carrier then
   return new; -- Editing an existing pen does not consume another place.
  end if;
 else
  sid:=new.show_id; cid:=new.source_cart_id; item_id:=new.source_cart_item_id; entry_id:=new.id;
  if new.scratched_at is not null or lower(coalesce(new.status,'')) in ('scratched','removed','cancelled') then return new; end if;
  if tg_op='UPDATE' and old.show_id=new.show_id and old.exhibitor_id=new.exhibitor_id
    and meat_pens_private.is_pen(old.class_name,old.species::text,old.is_fur)
    and old.scratched_at is null and lower(coalesce(old.status,'')) not in ('scratched','removed','cancelled') then
   return new;
  end if;
  -- BEFORE INSERT also runs for an idempotent ON CONFLICT checkout retry.
  if tg_op='INSERT' and new.source_cart_item_id is not null and exists(
    select 1 from public.entries e where e.source_cart_item_id=new.source_cart_item_id
      and e.show_id=sid and e.exhibitor_id=new.exhibitor_id and not e.is_fur
  ) then return new; end if;
 end if;
 select maximum into cap from meat_pens_private.entry_limits where show_id=sid;
 if not found then return new; end if;
 if new.exhibitor_id is null then raise exception 'Select an exhibitor for this meat pen.' using errcode='23514'; end if;
 perform pg_advisory_xact_lock(hashtextextended('meat-pen-limit:'||sid::text||':'||new.exhibitor_id::text,0));
 if meat_pens_private.used_places(sid,new.exhibitor_id,cid,entry_id,item_id)+1>cap then
  raise exception 'This show allows a maximum of % meat pen entries per exhibitor. Existing entries and this cart count toward the limit. Remove an extra pen or cancel an unfinished checkout before continuing.',cap using errcode='23514';
 end if;
 return new;
end; $$;
create trigger zz_meat_pen_entry_limit before insert or update on public.entry_cart_items
 for each row execute function meat_pens_private.enforce_entry_limit();
create trigger zz_meat_pen_entry_limit before insert or update on public.entries
 for each row execute function meat_pens_private.enforce_entry_limit();

create function meat_pens_private.validate_cart_limit(p_cart uuid) returns void
language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; cap integer; ex uuid;
begin
 select * into c from public.entry_carts where id=p_cart;
 if not found or c.status<>'active' then return; end if;
 select maximum into cap from meat_pens_private.entry_limits where show_id=c.show_id;
 if not found then return; end if;
 -- All entry points already hold their cart row lock. Consistent exhibitor
 -- order serializes simultaneous checkouts without reserving abandoned drafts.
 for ex in select distinct i.exhibitor_id from public.entry_cart_items i
  where i.cart_id=p_cart and meat_pens_private.is_pen(i.class_name,i.species::text,i.is_fur)
   and not i.is_checkin_fee_carrier and not i.is_exhibitor_fee_carrier and not i.is_show_addon_carrier
  order by i.exhibitor_id
 loop
  if ex is null then raise exception 'Select an exhibitor for this meat pen.' using errcode='23514'; end if;
  perform pg_advisory_xact_lock(hashtextextended('meat-pen-limit:'||c.show_id::text||':'||ex::text,0));
  if meat_pens_private.used_places(c.show_id,ex,p_cart)>cap then
   raise exception 'This show allows a maximum of % meat pen entries per exhibitor. Existing entries and this cart count toward the limit. Remove an extra pen or cancel an unfinished checkout before continuing.',cap using errcode='23514';
  end if;
 end loop;
end; $$;

-- Reject excess draft entries before a payment quote/provider charge, and on
-- free or pay-at-show checkout. Existing school/consent guards remain intact.
do $$declare sig text; d text; marker text:='  perform show_registration_private.validate_cart(p_cart_id);'; begin
 foreach sig in array array[
  'public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)',
  'public.commit_entry_cart_day_of(uuid)', 'public.commit_free_entry_cart(uuid)'
 ] loop
  d:=pg_get_functiondef(sig::regprocedure);
  if (length(d)-length(replace(d,marker,'')))/length(marker)<>1 then raise exception 'Meat pen checkout guard anchor changed: %',sig; end if;
  execute replace(d,marker,E'  perform meat_pens_private.validate_cart_limit(p_cart_id);\n'||marker);
 end loop;
end; $$;
revoke all on function meat_pens_private.is_pen(text,text,boolean),
 meat_pens_private.used_places(uuid,uuid,uuid,uuid,uuid),
 meat_pens_private.enforce_entry_limit(),meat_pens_private.validate_cart_limit(uuid)
 from public,anon,authenticated;
