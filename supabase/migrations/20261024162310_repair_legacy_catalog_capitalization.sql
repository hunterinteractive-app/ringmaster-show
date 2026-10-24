-- Case/whitespace-only cleanup with full before-images for rollback and proof
-- that judging results, ownership and payment fields remain unchanged.
create table variety_labels_private.legacy_case_repair (
  source_table text not null,
  row_id uuid not null,
  before_row jsonb not null,
  canonical_breed text,
  canonical_variety text,
  repaired_at timestamptz not null default now(),
  primary key(source_table,row_id)
);
alter table variety_labels_private.legacy_case_repair enable row level security;
revoke all on variety_labels_private.legacy_case_repair from public,anon,authenticated;

create temporary table catalog_case_rows on commit drop as
select 'animals'::text source_table,a.id row_id,to_jsonb(a) before_row,
       a.species::text species,a.breed,a.variety,null::uuid show_id
from public.animals a
union all
select 'entries',e.id,to_jsonb(e),e.species::text,e.breed,e.variety,e.show_id
from public.entries e
union all
select 'entry_cart_items',i.id,to_jsonb(i),i.species::text,i.breed,i.variety,c.show_id
from public.entry_cart_items i join public.entry_carts c on c.id=i.cart_id
-- Completed cart contents are historical receipts, not current animal records.
where c.status='active' and c.completed_payment_session_id is null
  and not i.is_checkin_fee_carrier and not i.is_exhibitor_fee_carrier and not i.is_show_addon_carrier;

create temporary table catalog_case_map on commit drop as
select k.*, jsonb_build_array(species,breed,variety,show_id) lookup_key,
 variety_labels_private.canonical_breed(species,breed,show_id) cb,
 variety_labels_private.canonical_variety(species,breed,variety,show_id) cv
from (select distinct species,breed,variety,show_id from catalog_case_rows) k;

insert into variety_labels_private.legacy_case_repair(source_table,row_id,before_row,canonical_breed,canonical_variety)
select r.source_table,r.row_id,r.before_row,m.cb,m.cv
from catalog_case_rows r join catalog_case_map m
 on m.lookup_key=jsonb_build_array(r.species,r.breed,r.variety,r.show_id)
where (r.breed is distinct from m.cb or r.variety is distinct from m.cv)
 and lower(regexp_replace(btrim(r.breed),'\s+',' ','g')) is not distinct from lower(regexp_replace(btrim(m.cb),'\s+',' ','g'))
 and lower(regexp_replace(btrim(r.variety),'\s+',' ','g')) is not distinct from lower(regexp_replace(btrim(m.cv),'\s+',' ','g'));

-- Take the lock before snapshot validation. The disabled lock guard is confined
-- to this atomic migration; concurrent app writes cannot slip through it.
set local lock_timeout='5s';
lock table public.animals, public.entries, public.entry_cart_items in share row exclusive mode;
do $$
begin
 if exists (
  select 1 from variety_labels_private.legacy_case_repair b
  join public.animals a on b.source_table='animals' and a.id=b.row_id where to_jsonb(a)<>b.before_row
  union all
  select 1 from variety_labels_private.legacy_case_repair b
  join public.entries e on b.source_table='entries' and e.id=b.row_id where to_jsonb(e)<>b.before_row
  union all
  select 1 from variety_labels_private.legacy_case_repair b
  join public.entry_cart_items i on b.source_table='entry_cart_items' and i.id=b.row_id where to_jsonb(i)<>b.before_row
 ) then raise exception 'A candidate changed during audit; retry the migration'; end if;
end $$;

update public.animals a set breed=b.canonical_breed,variety=b.canonical_variety
from variety_labels_private.legacy_case_repair b where b.source_table='animals' and a.id=b.row_id;

alter table public.entries disable trigger prevent_entry_changes_when_locked;
update public.entries e set breed=b.canonical_breed,variety=b.canonical_variety
from variety_labels_private.legacy_case_repair b where b.source_table='entries' and e.id=b.row_id;
-- Flush deferred result checks before restoring the lock guard.
set constraints all immediate;
alter table public.entries enable trigger prevent_entry_changes_when_locked;

update public.entry_cart_items i set breed=b.canonical_breed,variety=b.canonical_variety
from variety_labels_private.legacy_case_repair b where b.source_table='entry_cart_items' and i.id=b.row_id;

do $$
begin
 if exists (
  select 1 from variety_labels_private.legacy_case_repair b
  join public.animals a on b.source_table='animals' and a.id=b.row_id
  where to_jsonb(a)-array['breed','variety','updated_at'] <> b.before_row-array['breed','variety','updated_at']
     or a.breed is distinct from b.canonical_breed or a.variety is distinct from b.canonical_variety
  union all
  select 1 from variety_labels_private.legacy_case_repair b
  join public.entries e on b.source_table='entries' and e.id=b.row_id
  where to_jsonb(e)-array['breed','variety','updated_at'] <> b.before_row-array['breed','variety','updated_at']
     or e.breed is distinct from b.canonical_breed or e.variety is distinct from b.canonical_variety
  union all
  select 1 from variety_labels_private.legacy_case_repair b
  join public.entry_cart_items i on b.source_table='entry_cart_items' and i.id=b.row_id
  where to_jsonb(i)-array['breed','variety','updated_at'] <> b.before_row-array['breed','variety','updated_at']
     or i.breed is distinct from b.canonical_breed or i.variety is distinct from b.canonical_variety
 ) then raise exception 'Unexpected change beyond catalog labels; rolling back'; end if;
end $$;
