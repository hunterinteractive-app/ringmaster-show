-- Custom breeds belong to one show only. Global catalog breeds retain a NULL
-- local_show_id, so existing references and reporting continue to use breeds.id.
alter table public.breeds
  add column if not exists local_show_id uuid
  references public.shows(id) on delete cascade;

drop index if exists public.breeds_name_species_ci;

create unique index if not exists breeds_name_species_local_scope_ci
  on public.breeds (
    lower(name),
    species,
    coalesce(
      local_show_id,
      '00000000-0000-0000-0000-000000000000'::uuid
    )
  );

create index if not exists breeds_local_show_id_idx
  on public.breeds (local_show_id)
  where local_show_id is not null;

-- The existing breeds_write_super policy remains responsible for the shared
-- catalog. This policy permits a show owner or assigned show admin to manage
-- only rows that are explicitly local to that show.
drop policy if exists "breeds_manage_local_show" on public.breeds;

create policy "breeds_manage_local_show"
on public.breeds
for all
to authenticated
using (
  local_show_id is not null
  and (
    exists (
      select 1
      from public.shows s
      where s.id = breeds.local_show_id
        and (s.created_by = (select auth.uid()) or s.owner_user_id = (select auth.uid()))
    )
    or exists (
      select 1
      from public.show_admins sa
      where sa.show_id = breeds.local_show_id
        and sa.user_id = (select auth.uid())
    )
  )
)
with check (
  local_show_id is not null
  and (
    exists (
      select 1
      from public.shows s
      where s.id = breeds.local_show_id
        and (s.created_by = (select auth.uid()) or s.owner_user_id = (select auth.uid()))
    )
    or exists (
      select 1
      from public.show_admins sa
      where sa.show_id = breeds.local_show_id
        and sa.user_id = (select auth.uid())
    )
  )
);
