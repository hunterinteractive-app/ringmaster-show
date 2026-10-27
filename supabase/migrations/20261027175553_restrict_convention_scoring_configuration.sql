-- Convention is configured through trusted database access, not secretary UI.
-- The flag is preserved by ordinary show-settings saves, and direct API writes
-- cannot enable or clear it without a Super Admin's verified database role.
create or replace function public.guard_arba_convention_configuration()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if not coalesce(new.is_arba_convention, false) then return new; end if;
  elsif new.is_arba_convention is not distinct from old.is_arba_convention then
    return new;
  end if;

  if current_setting('role', true) = 'service_role'
     or public.is_super_admin(auth.uid())
     or (
       auth.uid() is null
       and current_user in ('postgres', 'supabase_admin')
       and coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon')
     ) then
    return new;
  end if;

  raise exception 'Only Super Admins can change ARBA Convention scoring.'
    using errcode = '42501';
end;
$$;

revoke all on function public.guard_arba_convention_configuration() from public, anon, authenticated;

create trigger guard_arba_convention_configuration
before insert or update of is_arba_convention on public.shows
for each row execute function public.guard_arba_convention_configuration();

comment on column public.shows.is_arba_convention is
  'Database-managed ARBA Convention flag; writable only by Super Admins or trusted database/service roles. Requires is_national_show=true and uses national_show_section_id (all sections when null). Secretary saves must omit this field.';
