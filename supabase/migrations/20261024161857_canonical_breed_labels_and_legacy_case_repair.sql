-- Complete the variety-label safeguard: canonicalize breed names as well.
-- Matching is species/show scoped and changes only case/whitespace, never typos,
-- aliases, COD status or historically judged classifications.
create or replace function variety_labels_private.canonical_breed(
  p_species text, p_breed text, p_show_id uuid default null
) returns text language sql stable set search_path = '' as $function$
  with candidates as (
    select b.name label, case when b.local_show_id=p_show_id then 0 else 1 end priority
    from public.breeds b
    where b.species::text=lower(btrim(p_species))
      and (b.local_show_id is null or b.local_show_id=p_show_id)
      and lower(regexp_replace(btrim(b.name), '\s+', ' ', 'g')) =
          lower(regexp_replace(btrim(p_breed), '\s+', ' ', 'g'))
  )
  select coalesce((select min(label) from candidates
    where priority=(select min(priority) from candidates)
    having count(distinct label)=1), p_breed);
$function$;
revoke all on function variety_labels_private.canonical_breed(text,text,uuid) from public;
grant execute on function variety_labels_private.canonical_breed(text,text,uuid) to authenticated, service_role;

create or replace function variety_labels_private.normalize_row()
returns trigger language plpgsql set search_path = '' as $function$
declare v_show_id uuid;
begin
  if TG_TABLE_NAME='entries' then
    v_show_id := NEW.show_id;
  elsif TG_TABLE_NAME='entry_cart_items' then
    select show_id into v_show_id from public.entry_carts where id=NEW.cart_id;
  end if;
  NEW.breed := variety_labels_private.canonical_breed(
    NEW.species::text, NEW.breed, v_show_id);
  NEW.variety := variety_labels_private.canonical_variety(
    NEW.species::text, NEW.breed, NEW.variety, v_show_id);
  return NEW;
end;
$function$;
revoke all on function variety_labels_private.normalize_row() from public;
