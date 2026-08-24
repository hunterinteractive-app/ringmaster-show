-- `exhibitors_owner_idx` provides the same owner_user_id lookup.
drop index if exists public.exhibitors_owner_user_id_idx;
