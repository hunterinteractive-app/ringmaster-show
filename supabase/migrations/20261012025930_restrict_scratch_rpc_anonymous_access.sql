-- Scratch changes require a signed-in user or the service role.
-- Explicit grants survive CREATE OR REPLACE and PUBLIC revocation.
revoke execute on function public.set_entry_scratch_state(uuid, boolean) from anon;
