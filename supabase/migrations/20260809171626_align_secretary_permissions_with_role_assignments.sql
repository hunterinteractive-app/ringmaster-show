-- The secretary UI writes to role_assignments.  Keep the older
-- show_role_assignments-based helpers compatible while granting the same
-- permissions to the current Show Secretary (admin) role.
create or replace function public.has_show_role(p_show_id uuid, p_role text, uid uuid)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.show_role_assignments sra
    where sra.show_id = p_show_id
      and sra.user_id = uid
      and sra.role = p_role
  )
  or exists (
    select 1
    from public.role_assignments ra
    where ra.show_id = p_show_id
      and ra.user_id = uid
      and (
        ra.role::text = p_role
        or (p_role = 'show_admin' and ra.role::text = 'admin')
      )
  );
$$;

create or replace function public.is_show_staff(p_show_id uuid, uid uuid)
returns boolean
language sql
stable
as $$
  select public.is_super_admin(uid)
     or exists (
          select 1
          from public.show_role_assignments sra
          where sra.show_id = p_show_id
            and sra.user_id = uid
        )
     or exists (
          select 1
          from public.role_assignments ra
          where ra.show_id = p_show_id
            and ra.user_id = uid
        );
$$;

drop policy if exists breeds_manage_local_show on public.breeds;
create policy breeds_manage_local_show
on public.breeds
for all
using (
  local_show_id is not null
  and (
    exists (
      select 1
      from public.shows s
      where s.id = breeds.local_show_id
        and (s.created_by = auth.uid() or s.owner_user_id = auth.uid())
    )
    or exists (
      select 1
      from public.show_admins sa
      where sa.show_id = breeds.local_show_id
        and sa.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.role_assignments ra
      where ra.show_id = breeds.local_show_id
        and ra.user_id = auth.uid()
        and ra.role::text = 'admin'
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
        and (s.created_by = auth.uid() or s.owner_user_id = auth.uid())
    )
    or exists (
      select 1
      from public.show_admins sa
      where sa.show_id = breeds.local_show_id
        and sa.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.role_assignments ra
      where ra.show_id = breeds.local_show_id
        and ra.user_id = auth.uid()
        and ra.role::text = 'admin'
    )
  )
);
