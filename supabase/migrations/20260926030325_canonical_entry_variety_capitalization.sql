-- Normalize new/edited variety values against the catalog without rewriting receipts.
create schema if not exists variety_labels_private;
grant usage on schema variety_labels_private to authenticated, service_role;

create or replace function variety_labels_private.canonical_variety(
  p_species text, p_breed text, p_variety text, p_show_id uuid default null
) returns text
language sql stable security invoker set search_path = ''
as $$
  select coalesce((
    select label from (
      select sv.custom_name as label, 0 as priority
      from public.show_varieties sv join public.breeds b on b.id=sv.breed_id
      where sv.show_id=p_show_id and sv.custom_name is not null
        and lower(btrim(b.name))=lower(btrim(p_breed))
        and lower(b.species::text)=lower(p_species)
      union all
      select v.name, 1 from public.varieties v
      join public.breeds b on b.id=v.breed_id
      where lower(btrim(b.name))=lower(btrim(p_breed))
        and lower(b.species::text)=lower(p_species)
        and (b.local_show_id is null or b.local_show_id=p_show_id)
      union all
      select c.variety_name, 2 from public.cavy_sop_variety_order c
      where lower(p_species)='cavy'
        and lower(btrim(c.breed_name))=lower(btrim(p_breed))
    ) candidates
    where lower(regexp_replace(btrim(label), '\s+', ' ', 'g'))=
          lower(regexp_replace(btrim(p_variety), '\s+', ' ', 'g'))
    order by priority, label collate "C" limit 1
  ), p_variety);
$$;
revoke all on function variety_labels_private.canonical_variety(text,text,text,uuid) from public;
grant execute on function variety_labels_private.canonical_variety(text,text,text,uuid) to authenticated, service_role;

create or replace function variety_labels_private.normalize_row()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_show_id uuid;
begin
  if TG_TABLE_NAME='entries' then
    v_show_id := NEW.show_id;
  elsif TG_TABLE_NAME='entry_cart_items' then
    select show_id into v_show_id from public.entry_carts where id=NEW.cart_id;
  end if;
  NEW.variety := variety_labels_private.canonical_variety(
    NEW.species::text, NEW.breed, NEW.variety, v_show_id);
  return NEW;
end;
$$;
revoke all on function variety_labels_private.normalize_row() from public;

create trigger canonical_variety_label
before insert or update of variety, breed, species on public.animals
for each row execute function variety_labels_private.normalize_row();
create trigger canonical_variety_label
before insert or update of variety, breed, species, cart_id on public.entry_cart_items
for each row execute function variety_labels_private.normalize_row();
create trigger canonical_variety_label
before insert or update of variety, breed, species, show_id on public.entries
for each row execute function variety_labels_private.normalize_row();
