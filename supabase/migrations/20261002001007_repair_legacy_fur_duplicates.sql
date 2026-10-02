-- Preserve complete evidence before removing proven, unjudged duplicates.
create table checkout_private.fur_duplicate_audit (
 entry_id uuid primary key,
 entry_snapshot jsonb not null,
 disposition text not null,
 reviewed_at timestamptz not null default now()
);
alter table checkout_private.fur_duplicate_audit enable row level security;
revoke all on checkout_private.fur_duplicate_audit from public,anon,authenticated;
grant all on checkout_private.fur_duplicate_audit to service_role;

-- Discover inbound entry foreign keys, including installations with extra modules.
create or replace function checkout_private.entry_has_references(p_entry uuid)
returns boolean language plpgsql set search_path='' as $$
declare ref record; found boolean;
begin
 for ref in select c.conrelid::regclass as relation,a.attname as column_name
 from pg_catalog.pg_constraint c join pg_catalog.pg_attribute a
 on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
 where c.confrelid='public.entries'::regclass and c.contype='f' loop
   execute format('select exists(select 1 from %s where %I=$1)',ref.relation,ref.column_name) into found using p_entry;
   if found then return true; end if;
 end loop;
 return false;
end $$;
revoke all on function checkout_private.entry_has_references(uuid) from public,anon,authenticated;

create or replace function checkout_private.repair_fur_duplicates()
returns integer language plpgsql set search_path='' as $$
declare candidate record; removed integer:=0; safe boolean;
begin
 for candidate in
   select to_jsonb(e) snapshot,e.* from public.entries e
   join public.entry_cart_items i on i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id
   where i.is_fur and not coalesce(e.is_fur,false)
   for update of e
 loop
   select not coalesce(s.is_locked,false)
   and candidate.snapshot->>'placement' is null and candidate.snapshot->>'fur_placement' is null
   and candidate.snapshot->>'special_awards' is null and candidate.snapshot->>'fur_award' is null
   and candidate.snapshot->>'result_status' is null and candidate.snapshot->>'result_entered_at' is null
   and exists(select 1 from public.entries f where f.source_cart_item_id=candidate.source_cart_item_id and f.source_cart_id=candidate.source_cart_id and f.is_fur)
   and exists(select 1 from public.entries r join public.entry_cart_items ri on ri.id=r.source_cart_item_id
     where r.show_id=candidate.show_id and r.section_id=candidate.section_id
       and r.exhibitor_id=candidate.exhibitor_id and r.animal_id=candidate.animal_id
       and r.source_cart_id=candidate.source_cart_id and not coalesce(r.is_fur,false) and not coalesce(ri.is_fur,false))
   and not checkout_private.entry_has_references(candidate.id)
   and not exists(select 1 from entry_refunds_private.entries where entry_id=candidate.id)
   into safe from public.shows s where s.id=candidate.show_id;
   insert into checkout_private.fur_duplicate_audit(entry_id,entry_snapshot,disposition)
   values(candidate.id,candidate.snapshot,case when safe then 'removed_confirmed_duplicate' else 'needs_historical_review' end)
   on conflict(entry_id) do nothing;
   if safe then
     delete from public.entries where id=candidate.id;
     removed:=removed+1;
   end if;
 end loop;
 return removed;
end $$;
revoke all on function checkout_private.repair_fur_duplicates() from public,anon,authenticated;
select checkout_private.repair_fur_duplicates();

-- Defense in depth: future checkout changes cannot reintroduce breed rows from
-- standalone fur items. Existing historical rows remain editable for review.
create function checkout_private.require_matching_cart_entry_kind()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(new.is_fur,false) and exists(
   select 1 from public.entry_cart_items i where i.id=new.source_cart_item_id
     and i.cart_id=new.source_cart_id and i.is_fur
 ) then
   raise exception 'A fur cart item cannot create a regular breed entry.';
 end if;
 return new;
end $$;
revoke all on function checkout_private.require_matching_cart_entry_kind() from public,anon,authenticated;
create trigger require_matching_cart_entry_kind
 before insert or update of source_cart_id,source_cart_item_id,is_fur on public.entries
 for each row execute function checkout_private.require_matching_cart_entry_kind();
