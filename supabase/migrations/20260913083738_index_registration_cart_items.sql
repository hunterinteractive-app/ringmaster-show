-- Checkout totals, registration completion and owner cart reads all filter by
-- cart_id. Avoid scanning every exhibitor's items during a purchase burst.
create index if not exists entry_cart_items_cart_id_idx
  on public.entry_cart_items (cart_id);
