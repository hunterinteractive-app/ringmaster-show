-- Kyle Walker's meat-pen shows use the supplied Houston handbook list.
-- Scope follows ownership, including future shows; ordinary breed entries and
-- other owners retain their existing rules. Catalog classification is unchanged.
-- SECURITY INVOKER preserves the caller's show/catalog visibility.
create function public.meat_pen_breeds(p_show_id uuid)
returns table(id uuid, name text, species text, class_system text)
language sql stable security invoker set search_path = ''
as $$
  select b.id, b.name, b.species::text, b.class_system::text
  from public.shows s
  cross join public.breeds b
  where s.id = p_show_id
    and b.species::text = 'rabbit' and b.is_active and b.local_show_id is null
    and case when s.owner_user_id = 'bca983ed-59ac-4615-a9a7-a2ce56d3d8e8'::uuid
      then b.name = any(array[
        'American', 'American Chinchilla', 'Argente Brun', 'Californian',
        'Champagne d''Argent', 'Cinnamon', 'Creme d''Argente',
        'New Zealand', 'Palomino', 'Satin', 'Rex'
      ])
      else b.class_system::text = 'six'
    end
  order by b.name;
$$;
revoke all on function public.meat_pen_breeds(uuid) from public, anon;
grant execute on function public.meat_pen_breeds(uuid) to authenticated, service_role;
comment on function public.meat_pen_breeds(uuid) is
  'Eligible master rabbit breeds for meat pens: Kyle Walker-owned shows use the handbook list including Rex; all other owners use active six-class breeds.';

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
      select 1 from public.meat_pen_breeds(v_show_id) b
      where lower(btrim(b.name)) = lower(btrim(new.breed))
    ) then
      raise exception 'This breed is not eligible for meat pens at this show.' using errcode = '23514';
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

