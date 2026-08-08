-- Keep email mandatory for all exhibitor records except the show expressly
-- listed in manual_exhibitor_information_policy.dart (Westmoreland Fair 2026).
alter table public.exhibitors
  alter column email drop not null;

alter table public.exhibitors
  drop constraint if exists exhibitors_email_required_except_name_only_manual_shows;

alter table public.exhibitors
  add constraint exhibitors_email_required_except_name_only_manual_shows
  check (
    email is not null
    or (
      is_local_only = true
      and created_for_show_id = '373d1b96-45bb-4f29-a630-96279ed0e91e'::uuid
    )
  );
