-- Keep show ownership independent of editable staff assignments.
-- Older shows recorded only created_by; retain any explicitly assigned owner.
create or replace function public.ensure_show_owner()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.owner_user_id is null then
    if tg_op = 'UPDATE' then
      new.owner_user_id := old.owner_user_id;
    end if;
    new.owner_user_id := coalesce(new.owner_user_id, new.created_by);
  end if;
  return new;
end;
$$;
revoke all on function public.ensure_show_owner() from public, anon, authenticated;

create trigger ensure_show_owner
before insert or update of owner_user_id, created_by on public.shows
for each row execute function public.ensure_show_owner();

update public.shows
set owner_user_id = created_by
where owner_user_id is null and created_by is not null;
