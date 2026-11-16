-- Stable meat-pen identity is independent of the rabbits' eventual tattoos.
create schema if not exists meat_pens_private;
revoke all on schema meat_pens_private from public, anon;
grant usage on schema meat_pens_private to authenticated;
create sequence meat_pens_private.pen_number;
create table meat_pens_private.enabled_shows (
 show_id uuid primary key references public.shows(id) on delete cascade
);
alter table meat_pens_private.enabled_shows enable row level security;
revoke all on table meat_pens_private.enabled_shows from public,anon,authenticated;
-- Resolve the requested show from its verified owner and show purpose.
insert into meat_pens_private.enabled_shows(show_id)
select id from public.shows where owner_user_id='bca983ed-59ac-4615-a9a7-a2ce56d3d8e8'
 and club_id='48522136-118e-4860-aa46-1abb2d783809'
 and name='Houston Livestock Show and Rodeo - Youth Meat Pen Show';

alter table public.entry_cart_items add column meat_pen_id text, add column meat_pen_tattoos text[];
alter table public.entries add column meat_pen_id text, add column meat_pen_tattoos text[];
create unique index entry_cart_items_meat_pen_id_key on public.entry_cart_items(meat_pen_id) where meat_pen_id is not null;
create unique index entries_meat_pen_id_key on public.entries(meat_pen_id) where meat_pen_id is not null;

create function meat_pens_private.enabled(p_show_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from meat_pens_private.enabled_shows where show_id=p_show_id);
$$;
create function public.meat_pen_registration_enabled(p_show_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$select meat_pens_private.enabled(p_show_id);$$;
revoke all on function meat_pens_private.enabled(uuid),public.meat_pen_registration_enabled(uuid) from public,anon;
grant execute on function meat_pens_private.enabled(uuid),public.meat_pen_registration_enabled(uuid) to authenticated;

create function meat_pens_private.identify() returns trigger
language plpgsql security definer set search_path='' as $$
declare sid uuid; source public.entry_cart_items%rowtype; values_changed boolean; render_label boolean; pen_number bigint;
begin
 if tg_table_name='entry_cart_items' then
  select show_id into sid from public.entry_carts where id=new.cart_id;
 else sid:=new.show_id; end if;
 if lower(btrim(coalesce(new.class_name,''))) not in ('meat pen','meat pens','meat_pen') or new.is_fur or new.species::text<>'rabbit' then
  if new.meat_pen_id is not null or new.meat_pen_tattoos is not null then
   raise exception 'Pen IDs belong to rabbit meat-pen entries.' using errcode='23514';
  end if;
  return new;
 end if;
 if tg_op='UPDATE' and old.meat_pen_id is not null then
  if new.meat_pen_id is distinct from old.meat_pen_id then
   raise exception 'The Pen ID cannot be changed.' using errcode='23514';
  end if;
  if tg_table_name='entry_cart_items' then
   if new.cart_id is distinct from old.cart_id then raise exception 'A Pen ID cannot move to another cart.' using errcode='23514'; end if;
  else
   if new.show_id is distinct from old.show_id then raise exception 'A Pen ID cannot move to another show.' using errcode='23514'; end if;
  end if;
  values_changed:=new.meat_pen_tattoos is distinct from old.meat_pen_tattoos;
  if new.tattoo is distinct from old.tattoo and not values_changed then
   raise exception 'Use Update tattoos to change a meat pen while keeping its Pen ID.' using errcode='23514';
  end if;
  if values_changed and new.meat_pen_tattoos is null then raise exception 'Enter all 3 tattoos, or select Tattoos not yet assigned.' using errcode='23514'; end if;
  render_label:=values_changed;
 else
  if new.meat_pen_id is not null then
   raise exception 'Pen IDs are assigned automatically.' using errcode='23514';
  end if;
  if not meat_pens_private.enabled(sid) then
   if new.meat_pen_tattoos is not null then
    raise exception 'Deferred meat-pen tattoos are not enabled for this show.' using errcode='23514';
   end if;
   return new;
  end if;
  render_label:=new.meat_pen_tattoos is not null or tg_op='UPDATE';
  if tg_table_name='entries' then
   if new.source_cart_item_id is not null then
    select i.* into source from public.entry_cart_items i join public.entry_carts c on c.id=i.cart_id
    where i.id=new.source_cart_item_id and i.cart_id=new.source_cart_id and c.show_id=sid
      and i.exhibitor_id=new.exhibitor_id and i.section_id=new.section_id;
    if not found then raise exception 'Meat pen does not match its source cart.' using errcode='23514'; end if;
    if source.meat_pen_id is not null then
     new.meat_pen_id:=source.meat_pen_id;
     new.meat_pen_tattoos:=source.meat_pen_tattoos;
     render_label:=true;
    end if;
   end if;
  end if;
  if new.meat_pen_id is null then
   pen_number:=nextval('meat_pens_private.pen_number');
   new.meat_pen_id:='MP-'||lpad(pen_number::text,greatest(6,length(pen_number::text)),'0');
  end if;
  -- Preserve legacy input exactly, including placeholder tattoos. Never guess
  -- that an existing value should be discarded or marked as a real tattoo.
  if new.meat_pen_tattoos is null then
   new.meat_pen_tattoos:=regexp_split_to_array(coalesce(new.tattoo,''),'\s*/\s*');
   if cardinality(new.meat_pen_tattoos)<>3 or ''=any(new.meat_pen_tattoos) then
    new.meat_pen_tattoos:=null;
   end if;
  end if;
 end if;
 if new.meat_pen_tattoos is not null then
  if cardinality(new.meat_pen_tattoos) not in (0,3) or exists(
   select 1 from unnest(new.meat_pen_tattoos) t where t is null or btrim(t)='' or length(t)>40 or t~'[|/]'
  ) then raise exception 'Enter all 3 tattoos, or select Tattoos not yet assigned.' using errcode='23514'; end if;
  select coalesce(array_agg(upper(btrim(t)) order by ord),'{}'::text[]) into new.meat_pen_tattoos
  from unnest(new.meat_pen_tattoos) with ordinality as u(t,ord);
 end if;
 if render_label then
  if new.animal_id is null and (new.animal_name is null or new.animal_name=new.tattoo) then
   new.animal_name:='Pen '||new.meat_pen_id;
  end if;
  new.tattoo:=new.meat_pen_id||' | '||case
   when new.meat_pen_tattoos is null then coalesce(new.tattoo,'Tattoos not yet assigned')
   when cardinality(new.meat_pen_tattoos)=0 then 'Tattoos not yet assigned'
   else array_to_string(new.meat_pen_tattoos,' / ') end;
 end if;
 return new;
end;$$;
revoke all on function meat_pens_private.identify() from public,anon,authenticated;
create trigger identify_meat_pen before insert or update on public.entry_cart_items
 for each row execute function meat_pens_private.identify();
create trigger identify_meat_pen before insert or update on public.entries
 for each row execute function meat_pens_private.identify();

create table meat_pens_private.tattoo_changes (
 id bigint generated always as identity primary key,
 entry_id uuid not null, pen_id text not null, changed_by uuid,
 old_tattoos text[], new_tattoos text[], changed_at timestamptz not null default now()
);
alter table meat_pens_private.tattoo_changes enable row level security;
revoke all on table meat_pens_private.tattoo_changes from public,anon,authenticated;
create function meat_pens_private.audit_tattoos() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if old.meat_pen_id is not null and new.meat_pen_tattoos is distinct from old.meat_pen_tattoos then
  insert into meat_pens_private.tattoo_changes(entry_id,pen_id,changed_by,old_tattoos,new_tattoos)
  values(new.id,new.meat_pen_id,auth.uid(),old.meat_pen_tattoos,new.meat_pen_tattoos);
 end if; return new;
end;$$;
revoke all on function meat_pens_private.audit_tattoos() from public,anon,authenticated;
create trigger audit_meat_pen_tattoos after update on public.entries
 for each row execute function meat_pens_private.audit_tattoos();

create function meat_pens_private.update_tattoos(p_entry_id uuid,p_tattoos text[]) returns void
language plpgsql security definer set search_path='' as $$
declare e public.entries%rowtype;
begin
 select * into e from public.entries where id=p_entry_id for update;
 if not found or auth.uid() is null or not (
  coalesce(public.user_can_manage_entries(e.show_id),false) or exists(
   select 1 from public.exhibitors x where x.id=e.exhibitor_id and household_private.has_access(x.owner_user_id)
  )
 ) then raise exception 'You do not have permission to update this meat pen.' using errcode='42501'; end if;
 if (select s.is_locked from public.shows s where s.id=e.show_id) then
  raise exception 'Show is locked. Changes are not allowed.';
 end if;
 if e.meat_pen_id is null then raise exception 'This entry does not have a Pen ID.'; end if;
 if e.scratched_at is not null or lower(coalesce(e.status,'')) in ('scratched','removed','cancelled') then
  raise exception 'Tattoos cannot be changed on a scratched or removed entry.';
 end if;
 if p_tattoos is null or cardinality(p_tattoos)<>3 then raise exception 'Enter all 3 tattoos.'; end if;
 -- Entry deadlines do not prevent adding identification. Existing locked-show
 -- and refund-in-progress triggers still apply. No fees or payments are edited.
 update public.entries set meat_pen_tattoos=p_tattoos where id=e.id;
end;$$;
create function public.update_meat_pen_tattoos(p_entry_id uuid,p_tattoos text[]) returns void
language sql security invoker set search_path='' as $$select meat_pens_private.update_tattoos(p_entry_id,p_tattoos);$$;
revoke all on function meat_pens_private.update_tattoos(uuid,text[]),public.update_meat_pen_tattoos(uuid,text[]) from public,anon;
grant execute on function meat_pens_private.update_tattoos(uuid,text[]),public.update_meat_pen_tattoos(uuid,text[]) to authenticated;

-- Existing entered pens receive an ID without deleting any supplied tattoos.
-- Submitted cart/payment snapshots are left untouched.
update public.entries e set tattoo=e.tattoo
where meat_pens_private.enabled(e.show_id) and e.meat_pen_id is null
 and lower(btrim(e.class_name)) in ('meat pen','meat pens','meat_pen') and not e.is_fur
 and not exists(select 1 from public.shows s where s.id=e.show_id and s.is_locked);
