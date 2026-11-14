-- A section or exhibitor move must retain the original checkout relationship.
-- The original receipt is immutable; Show Finances projects it onto the current
-- entry owner/section. In-place moves remain subject to existing entry RLS.
create function show_finances_private.preserve_entry_payment_provenance()
returns trigger language plpgsql set search_path='' as $$
begin
 if (old.source_cart_id is not null and new.source_cart_id is distinct from old.source_cart_id)
  or (old.source_cart_item_id is not null and new.source_cart_item_id is distinct from old.source_cart_item_id)
  or (old.source_cart_id is not null and new.show_id is distinct from old.show_id) then
  raise exception 'Keep the original checkout link when moving an entry. Use Move to another section instead of removing and recreating it.' using errcode='23514';
 end if;
 return new;
end $$;
revoke all on function show_finances_private.preserve_entry_payment_provenance() from public,anon,authenticated;
create trigger preserve_entry_payment_provenance before update of source_cart_id,source_cart_item_id,show_id
 on public.entries for each row execute function show_finances_private.preserve_entry_payment_provenance();

-- Include source-item changes and the original payer when repairing provenance.
-- Refresh both sides of Open/Youth and exhibitor moves in deterministic order.
create or replace function manual_entry_balances_private.entries_changed()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record; v_changed jsonb;
begin
 if current_setting('ringmaster.manual_balance_refresh',true)='on' then return null; end if;
 if tg_op='INSERT' then
  select jsonb_agg(to_jsonb(n)) into v_changed from new_rows n;
 elsif tg_op='DELETE' then
  select jsonb_agg(to_jsonb(o)) into v_changed from old_rows o;
 else
  select jsonb_agg(to_jsonb(c)) into v_changed from (
   (select show_id,exhibitor_id,section_id,source_cart_id,source_cart_item_id,is_fur,scratched_at,is_test,status from new_rows
    except all select show_id,exhibitor_id,section_id,source_cart_id,source_cart_item_id,is_fur,scratched_at,is_test,status from old_rows)
   union
   (select show_id,exhibitor_id,section_id,source_cart_id,source_cart_item_id,is_fur,scratched_at,is_test,status from old_rows
    except all select show_id,exhibitor_id,section_id,source_cart_id,source_cart_item_id,is_fur,scratched_at,is_test,status from new_rows)
  ) c;
 end if;
 for r in
  with changed as (select * from jsonb_to_recordset(coalesce(v_changed,'[]')) c(show_id uuid,exhibitor_id uuid,source_cart_id uuid,source_cart_item_id uuid))
  select show_id,exhibitor_id from changed
  union select c.show_id,i.exhibitor_id from changed c join public.entry_cart_items i on i.id=c.source_cart_item_id and i.cart_id=c.source_cart_id
  order by show_id,exhibitor_id
 loop
  perform manual_entry_balances_private.refresh(r.show_id,r.exhibitor_id);
 end loop;
 return null;
end $$;
