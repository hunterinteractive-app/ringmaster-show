-- Supabase may grant EXECUTE through role defaults. This helper is only for
-- the checked request/review functions and must never be an API endpoint.
revoke all on function public.apply_checkin_entry_changes(uuid, jsonb, text, uuid, uuid)
  from public, anon, authenticated;
