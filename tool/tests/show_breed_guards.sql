-- Standalone regression: run with psql in an EMPTY disposable database.
\set ON_ERROR_STOP on
create role authenticated;
create role service_role bypassrls;
create type public.species as enum ('rabbit', 'cavy');
create table public.shows (id uuid primary key, is_published boolean default true);
create table public.breeds (id uuid primary key, name text, species public.species);
create table public.show_breeds (show_id uuid, breed_id uuid, is_enabled boolean);
create table public.entry_carts (id uuid primary key, show_id uuid);
create table public.entry_cart_items (
  cart_id uuid, breed text, species text, is_checkin_fee_carrier boolean default false
);
create table public.entries (show_id uuid, breed text, species public.species, scratched_at timestamptz);
alter table public.show_breeds enable row level security;
grant usage on schema public to authenticated, service_role;
grant select on all tables in schema public to authenticated, service_role;
grant insert, update on public.entry_cart_items, public.entries to authenticated, service_role;

\ir ../../supabase/migrations/20260909200245_enforce_show_breeds_on_cart_items_and_entries.sql

insert into shows values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
insert into breeds values
 ('00000000-0000-0000-0000-000000000011', 'American', 'cavy'),
 ('00000000-0000-0000-0000-000000000012', 'American', 'rabbit'),
 ('00000000-0000-0000-0000-000000000013', 'Beveren', 'rabbit');
insert into show_breeds values
 ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000011', true),
 ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000012', false),
 ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000013', false);
insert into entry_carts values ('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001');

set role authenticated;
do $$
declare
 s uuid := '00000000-0000-0000-0000-000000000001';
 c uuid := '00000000-0000-0000-0000-000000000021';
 q text;
begin
 if (select count(*) from show_breeds where show_id=s) <> 3 then
   raise exception 'Exhibitors cannot see breed settings';
 end if;
 if not show_allows_entry_breed(s, ' American ', ' CAVY ') then raise exception 'Enabled cavy rejected'; end if;
 if show_allows_entry_breed(s, 'American', 'rabbit') then raise exception 'Same-name rabbit allowed'; end if;
 if show_allows_entry_breed(s, 'Unknown', 'cavy') then raise exception 'Unlisted breed allowed'; end if;
 if show_allows_entry_breed(null, 'American', 'cavy') then raise exception 'Missing show allowed'; end if;
 if not show_allows_entry_breed('00000000-0000-0000-0000-000000000002', 'Beveren', 'rabbit') then raise exception 'Legacy fallback broken'; end if;

 insert into entry_cart_items(cart_id,breed,species) values(c,'American','cavy');
 insert into entries(show_id,breed,species) values(s,'American','cavy');
 insert into entry_cart_items(cart_id,is_checkin_fee_carrier) values(c,true);
 foreach q in array array[
   format('insert into entry_cart_items(cart_id,breed,species) values(%L,''Beveren'',''rabbit'')',c),
   format('insert into entries(show_id,breed,species) values(%L,''Beveren'',''rabbit'')',s),
   format('insert into entries(show_id,breed,species) values(%L,''American'',''rabbit'')',s),
   format('insert into entries(show_id,breed,species) values(%L,null,''cavy'')',s),
   'update entry_cart_items set species=''rabbit'' where not is_checkin_fee_carrier',
   'update entries set species=''rabbit''',
   'update entry_cart_items set is_checkin_fee_carrier=false where is_checkin_fee_carrier'
 ] loop
   begin
     execute q;
     raise exception 'Invalid write succeeded: %',q;
   exception when check_violation then
     if sqlerrm not like 'The breed % is not enabled for this show.' then raise; end if;
   end;
 end loop;
end;
$$;
reset role;

-- An animal already in a cart must be checked again after configuration changes.
update show_breeds set is_enabled=false;
set role service_role;
do $$
begin
 begin
   insert into entries(show_id,breed,species)
   select c.show_id,i.breed,i.species::public.species
   from entry_cart_items i join entry_carts c on c.id=i.cart_id
   where not i.is_checkin_fee_carrier;
   raise exception 'Stale cart accepted at checkout';
 exception when check_violation then null;
 end;
 update entries set scratched_at=now();
 if not found then raise exception 'Historical entry scratch failed'; end if;
end;
$$;
reset role;
select 'PASS: exhibitor reads, enabled cavy, species matching, invalid inserts/updates, fee carriers, stale checkout, legacy fallback, historical scratch' as result;
