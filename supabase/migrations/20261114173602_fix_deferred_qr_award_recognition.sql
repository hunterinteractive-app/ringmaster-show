-- Deferred constraint triggers run after the SECURITY DEFINER save RPC returns.
-- Their reads must see the saved row, not the caller's RLS-filtered view. These
-- trigger-only validators expose no data and retain every recognition rule.
alter function public.validate_retired_awards() set schema catalog_recognition_private;
alter function catalog_recognition_private.validate_retired_awards() security definer;
alter function catalog_recognition_private.validate_retired_awards() set search_path = '';
revoke all on function catalog_recognition_private.validate_retired_awards() from public,anon,authenticated;

-- The COD check otherwise silently skips a row hidden from an anonymous writer.
alter function show_awards_private.validate_cod_awards() security definer;
alter function show_awards_private.validate_cod_awards() set search_path = '';
revoke all on function show_awards_private.validate_cod_awards() from public,anon,authenticated;
notify pgrst,'reload schema';
