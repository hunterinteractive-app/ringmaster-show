create schema extensions;
create extension pgtap with schema extensions;
create table public.shows(id uuid primary key,is_published boolean default true);
create table public.breeds(id uuid primary key default gen_random_uuid(),name text,species text,class_system text,is_active boolean,local_show_id uuid);
create table public.show_breeds(show_id uuid,breed_id uuid,is_enabled boolean);
create table public.show_sections(id uuid primary key,show_id uuid,is_enabled boolean,breed_scope text,allow_meat_classes boolean);
create table public.show_commercial_classes(show_id uuid,class_code text,is_enabled boolean);
create table public.entry_carts(id uuid primary key,show_id uuid);
create table public.entry_cart_items(id uuid primary key default gen_random_uuid(),cart_id uuid,section_id uuid,breed text,species text,class_name text,is_fur boolean default false,is_checkin_fee_carrier boolean default false);
create table public.entries(id uuid primary key default gen_random_uuid(),show_id uuid,section_id uuid,breed text,species text,class_name text,is_fur boolean default false);
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

alter table public.show_commercial_classes enable row level security;
grant select on public.shows,public.breeds,public.show_breeds,public.show_sections,public.show_commercial_classes,public.entry_carts to authenticated;
grant select,insert on public.entry_cart_items to authenticated;

grant usage on schema extensions to authenticated;
