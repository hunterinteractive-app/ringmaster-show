-- A show creator may manage the breed availability rows for their own show.
-- This complements the existing super-admin and show-admin policies without
-- granting access to any other show.
drop policy if exists "show_breeds_manage_creator" on public.show_breeds;

create policy "show_breeds_manage_creator"
on public.show_breeds
for all
to authenticated
using (
  exists (
    select 1
    from public.shows s
    where s.id = show_breeds.show_id
      and s.created_by = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.shows s
    where s.id = show_breeds.show_id
      and s.created_by = (select auth.uid())
  )
);
