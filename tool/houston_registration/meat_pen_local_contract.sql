-- Match the existing hosted commercial-class columns in the older local
-- rehearsal baseline. This file is local fixture support, not a deployment.
alter table public.show_sections add column if not exists allow_meat_classes boolean not null default false;
create table if not exists public.show_commercial_classes (
 show_id uuid not null references public.shows(id), class_code text not null,
 display_name text not null, is_enabled boolean not null default true,
 sort_order integer not null default 0, updated_at timestamptz not null default now(),
 primary key(show_id,class_code)
);
alter table public.show_commercial_classes enable row level security;
grant select on public.show_commercial_classes to authenticated;
