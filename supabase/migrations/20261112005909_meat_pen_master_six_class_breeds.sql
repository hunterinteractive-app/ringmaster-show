-- Exhibitors must be able to read published commercial-class configuration,
-- both for the entry picker and the security-invoker validation below.
create policy show_commercial_classes_read_published_show
on public.show_commercial_classes for select to authenticated
using (exists (select 1 from public.shows s
  where s.id = show_commercial_classes.show_id and s.is_published = true));

-- Meat pens have their own commercial-class eligibility. Disabling ordinary
-- breed entries must not disable a configured meat-pen section.
create or replace function public.enforce_show_entry_breed()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_show_id uuid;
begin
  if tg_table_name = 'entry_cart_items' then
    if new.is_checkin_fee_carrier then return new; end if;
    select c.show_id into v_show_id from public.entry_carts c where c.id = new.cart_id;
  else
    v_show_id := new.show_id;
  end if;

  if lower(btrim(coalesce(new.class_name, ''))) in ('meat pen', 'meat pens', 'meat_pen') then
    if lower(coalesce(new.species::text, '')) <> 'rabbit' or coalesce(new.is_fur, false) then
      raise exception 'Meat pens must be rabbit entries, not fur entries.' using errcode = '23514';
    end if;
    if not exists (
      select 1 from public.show_sections ss
      where ss.id = new.section_id and ss.show_id = v_show_id
        and ss.is_enabled
        and (ss.breed_scope = 'meat_only' or ss.allow_meat_classes)
    ) or not exists (
      select 1 from public.show_commercial_classes cc
      where cc.show_id = v_show_id and cc.class_code = 'meat_pen' and cc.is_enabled
    ) then
      raise exception 'Meat Pens are not enabled for the selected show section.' using errcode = '23514';
    end if;
    if not exists (
      select 1 from public.breeds b
      where b.species::text = 'rabbit' and b.class_system::text = 'six'
        and b.is_active and b.local_show_id is null
        and lower(btrim(b.name)) = lower(btrim(new.breed))
    ) then
      raise exception 'Meat pens require an active six-class rabbit breed from the master catalog.' using errcode = '23514';
    end if;
    return new;
  end if;

  if public.show_allows_entry_breed(v_show_id, new.breed, new.species::text) is not true then
    raise exception 'The breed % (%) is not enabled for this show.',
      coalesce(nullif(btrim(new.breed), ''), 'Unknown'),
      coalesce(new.species::text, 'unknown species')
      using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_show_entry_breed() from public;

-- Recheck changes that could turn a meat pen into a regular entry or move it
-- into a section without commercial classes. Checkout revalidates entries too.
drop trigger if exists enforce_cart_item_show_breed on public.entry_cart_items;
create trigger enforce_cart_item_show_breed
before insert or update of cart_id, section_id, breed, species, class_name, is_fur, is_checkin_fee_carrier
on public.entry_cart_items for each row execute function public.enforce_show_entry_breed();
drop trigger if exists enforce_entry_show_breed on public.entries;
create trigger enforce_entry_show_breed
before insert or update of show_id, section_id, breed, species, class_name, is_fur
on public.entries for each row execute function public.enforce_show_entry_breed();
