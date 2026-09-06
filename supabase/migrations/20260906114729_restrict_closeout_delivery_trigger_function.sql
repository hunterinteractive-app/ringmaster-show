-- This SECURITY DEFINER helper exists only for its database trigger. It must
-- not be callable through PostgREST by anonymous or signed-in clients.
revoke execute on function public.sync_closeout_club_sent_date_from_delivery()
from public, anon, authenticated;
