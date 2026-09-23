-- Match show_breeds_manage_creator without changing existing staff/admin access.
create policy show_varieties_manage_creator
on public.show_varieties
for all to authenticated
using (
  exists (select 1 from public.shows s
          where s.id = show_varieties.show_id
            and s.created_by = (select auth.uid()))
)
with check (
  exists (select 1 from public.shows s
          where s.id = show_varieties.show_id
            and s.created_by = (select auth.uid()))
);
