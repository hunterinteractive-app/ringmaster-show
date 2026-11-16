-- Tattoo changes close at the entry deadline, not at show locking.
create or replace function meat_pens_private.update_tattoos(p_entry_id uuid,p_tattoos text[]) returns void
language plpgsql security definer set search_path='' as $$
declare e public.entries%rowtype; close_at timestamptz; locked boolean;
begin
 select * into e from public.entries where id=p_entry_id for update;
 if not found or auth.uid() is null or not (
  coalesce(public.user_can_manage_entries(e.show_id),false) or exists(
   select 1 from public.exhibitors x where x.id=e.exhibitor_id and household_private.has_access(x.owner_user_id)
  )
 ) then raise exception 'You do not have permission to update this meat pen.' using errcode='42501'; end if;
 select s.entry_close_at,s.is_locked into close_at,locked
 from public.shows s where s.id=e.show_id for share;
 if locked then
  raise exception 'Show is locked. Changes are not allowed.';
 end if;
 if close_at is not null and clock_timestamp()>=close_at then
  raise exception 'Entry deadline passed. Tattoos can no longer be changed.';
 end if;
 if e.meat_pen_id is null then raise exception 'This entry does not have a Pen ID.'; end if;
 if e.scratched_at is not null or lower(coalesce(e.status,'')) in ('scratched','removed','cancelled') then
  raise exception 'Tattoos cannot be changed on a scratched or removed entry.';
 end if;
 if p_tattoos is null or cardinality(p_tattoos)<>3 then raise exception 'Enter all 3 tattoos.'; end if;
 -- Existing locked-show and refund-in-progress protections still apply.
 -- No fees or payments are edited.
 update public.entries set meat_pen_tattoos=p_tattoos where id=e.id;
end;$$;

-- Enforce the same cutoff on direct entry updates, including staff updates.
-- Existing row permissions still determine who can update an entry.
create function meat_pens_private.enforce_tattoo_deadline() returns trigger
language plpgsql security definer set search_path='' as $$
declare close_at timestamptz;
begin
 if old.meat_pen_id is not null and new.meat_pen_tattoos is distinct from old.meat_pen_tattoos then
  select s.entry_close_at into close_at from public.shows s where s.id=new.show_id for share;
  if close_at is not null and clock_timestamp()>=close_at then
   raise exception 'Entry deadline passed. Tattoos can no longer be changed.';
  end if;
 end if;
 return new;
end;$$;
revoke all on function meat_pens_private.enforce_tattoo_deadline() from public,anon,authenticated;
create trigger meat_pen_tattoo_deadline before update of meat_pen_tattoos on public.entries
 for each row execute function meat_pens_private.enforce_tattoo_deadline();
