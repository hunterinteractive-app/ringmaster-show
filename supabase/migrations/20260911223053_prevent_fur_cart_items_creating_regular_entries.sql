-- Fur/wool add-ons are separate cart items, not a regular-entry checkbox.
-- Preserve the current payment/authorization implementation and change only
-- the regular-entry INSERT in both completion paths. Fail closed on drift.
do $migration$
declare
  signature text;
  definition text;
  old_clause text := E'where i.cart_id = p_cart_id\n  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)';
  new_clause text := E'where i.cart_id = p_cart_id and not coalesce(i.is_fur, false)\n  on conflict (source_cart_id, source_cart_item_id, cart_entry_kind)';
begin
  foreach signature in array array[
    'public.commit_entry_cart_day_of(uuid)',
    'public.finalize_entry_cart_paid(uuid,uuid,text,text,integer,text)'
  ] loop
    definition := pg_get_functiondef(signature::regprocedure);
    if strpos(definition, new_clause) > 0 then
      continue;
    end if;
    if (length(definition) - length(replace(definition, old_clause, '')))
         / length(old_clause) <> 1 then
      raise exception 'Expected exactly one regular-entry INSERT in %', signature;
    end if;
    execute replace(definition, old_clause, new_clause);
  end loop;
end;
$migration$;
