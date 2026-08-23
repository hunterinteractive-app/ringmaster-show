-- Keep Entry Management and its remove action on the same authorization
-- boundary.  A superintendent and reporting clerk can add/edit entries, so
-- they must also be able to remove a mistaken entry while the show is open.
-- The entries lock trigger continues to reject every modification after lock.
create or replace function public.user_can_manage_entries(
  p_show_id uuid,
  p_user_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.user_can_manage_show_settings(
      p_show_id,
      coalesce(p_user_id, auth.uid())
    )
    or exists (
      select 1
      from public.role_assignments ra
      where ra.show_id = p_show_id
        and ra.user_id = coalesce(p_user_id, auth.uid())
        and ra.role in ('superintendent', 'reporting_clerk')
    );
$$;

drop policy if exists entries_delete_owner_or_show_admin on public.entries;

create policy entries_delete_owner_or_show_entry_staff
on public.entries
for delete
to authenticated
using (
  exhibitor_user_id = (select auth.uid())
  or public.user_can_manage_entries(show_id)
);
