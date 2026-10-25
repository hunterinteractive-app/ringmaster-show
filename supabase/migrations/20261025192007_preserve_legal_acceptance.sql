-- Old open browser tabs can still submit an earlier published policy version.
-- Preserve a newer receipt and its original timestamp instead of rolling it back.
-- This never marks an unaccepted policy accepted or changes existing receipts.
create schema if not exists legal_acceptance_private;
revoke all on schema legal_acceptance_private from public,anon,authenticated;

create function legal_acceptance_private.preserve_profile_acceptance()
returns trigger language plpgsql security invoker set search_path='' as $$
declare
 terms_versions constant text[]:=array['2026-05','2026-09'];
 privacy_versions constant text[]:=array['2026-05','2026-09','2026-10','2026-10-25-locality'];
begin
 if old.accepted_terms_version is not null and (
   new.accepted_terms_version is null
   or new.accepted_terms_version=old.accepted_terms_version
   or array_position(terms_versions,new.accepted_terms_version)<array_position(terms_versions,old.accepted_terms_version)
 ) then
   new.accepted_terms_version:=old.accepted_terms_version;
   new.accepted_terms_at:=old.accepted_terms_at;
 end if;
 if old.accepted_privacy_version is not null and (
   new.accepted_privacy_version is null
   or new.accepted_privacy_version=old.accepted_privacy_version
   or array_position(privacy_versions,new.accepted_privacy_version)<array_position(privacy_versions,old.accepted_privacy_version)
 ) then
   new.accepted_privacy_version:=old.accepted_privacy_version;
   new.accepted_privacy_at:=old.accepted_privacy_at;
 end if;
 return new;
end;
$$;
revoke all on function legal_acceptance_private.preserve_profile_acceptance() from public,anon,authenticated;
create trigger preserve_profile_legal_acceptance
before update of accepted_terms_version,accepted_terms_at,accepted_privacy_version,accepted_privacy_at
on public.profiles for each row execute function legal_acceptance_private.preserve_profile_acceptance();
