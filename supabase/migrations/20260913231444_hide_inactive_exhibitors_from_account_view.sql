-- A display preference for the account list, not deletion or ownership transfer.
alter table public.exhibitors add column account_hidden_at timestamptz;
alter table public.exhibitors add constraint exhibitors_hide_inactive_only
 check (account_hidden_at is null or is_active is not true);
comment on column public.exhibitors.account_hidden_at is
 'Hides an inactive exhibitor from Account Settings only. Ownership and historical entries remain intact.';
create function public.restore_reactivated_exhibitor_visibility() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
 if new.is_active is true then new.account_hidden_at := null; end if;
 return new;
end $$;
revoke all on function public.restore_reactivated_exhibitor_visibility() from public,anon,authenticated;
create trigger restore_reactivated_exhibitor_visibility
 before update of is_active on public.exhibitors
 for each row execute function public.restore_reactivated_exhibitor_visibility();
