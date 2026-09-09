-- Entry selection already reads these settings. Without a read policy ordinary
-- exhibitors see an empty list and the legacy all-breeds fallback is activated.
create policy show_breeds_read_published_show
on public.show_breeds for select to authenticated
using (exists (
  select 1 from public.shows s
  where s.id = show_breeds.show_id and s.is_published = true
));

create or replace function public.show_allows_entry_breed(
  p_show_id uuid, p_breed text, p_species text
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (select 1 from public.shows s where s.id = p_show_id)
    and nullif(btrim(p_breed), '') is not null
    and lower(btrim(p_species)) in ('rabbit', 'cavy')
    and (
      -- Preserve the entry screen's legacy behavior for unconfigured shows.
      not exists (select 1 from public.show_breeds sb where sb.show_id = p_show_id)
      or exists (
        select 1
        from public.show_breeds sb
        join public.breeds b on b.id = sb.breed_id
        where sb.show_id = p_show_id
          and sb.is_enabled
          and lower(btrim(b.name)) = lower(btrim(p_breed))
          and lower(btrim(b.species::text)) = lower(btrim(p_species))
      )
    );
$$;

revoke all on function public.show_allows_entry_breed(uuid, text, text) from public;
grant execute on function public.show_allows_entry_breed(uuid, text, text)
  to authenticated, service_role;

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
    -- Fee carriers represent charges, not animals, and are skipped by the
    -- existing entry-insert trigger during checkout.
    if new.is_checkin_fee_carrier then return new; end if;
    select c.show_id into v_show_id from public.entry_carts c where c.id = new.cart_id;
  else
    v_show_id := new.show_id;
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

create trigger enforce_cart_item_show_breed
before insert or update of cart_id, breed, species, is_checkin_fee_carrier
on public.entry_cart_items
for each row execute function public.enforce_show_entry_breed();

-- This also rechecks old carts at checkout and covers direct/admin entries,
-- including entries without a section. Scratch/result-only updates still work.
create trigger enforce_entry_show_breed
before insert or update of show_id, breed, species
on public.entries
for each row execute function public.enforce_show_entry_breed();
