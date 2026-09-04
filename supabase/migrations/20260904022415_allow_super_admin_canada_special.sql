-- Canada Special remains secretary-scoped, but super administrators need to
-- configure and test it without being added to each feature allowlist.

create or replace function public.enforce_canada_special_discount_access()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_changed boolean;
begin
  if tg_op = 'INSERT' then
    v_changed :=
      new.canada_special_discount_enabled
      or new.canada_special_discount_type <> 'amount'
      or new.canada_special_discount_value <> 0
      or new.canada_special_discount_scope <> 'both';
  else
    v_changed :=
      new.canada_special_discount_enabled is distinct from old.canada_special_discount_enabled
      or new.canada_special_discount_type is distinct from old.canada_special_discount_type
      or new.canada_special_discount_value is distinct from old.canada_special_discount_value
      or new.canada_special_discount_scope is distinct from old.canada_special_discount_scope;
  end if;

  if not v_changed then
    return new;
  end if;

  -- Server jobs remain authorized. Interactive changes require either global
  -- super-admin access or a feature-specific secretary allowlist row.
  if current_user in ('postgres', 'service_role')
     or coalesce(auth.jwt() ->> 'role', '') = 'service_role'
     or public.is_super_admin((select auth.uid())) then
    return new;
  end if;

  if not exists (
    select 1
    from public.secretary_feature_access access
    where access.feature_key = 'canada_special_discount'
      and access.user_id = (select auth.uid())
  ) then
    raise exception 'Canada Special is not enabled for this secretary account'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_canada_special_discount_access()
  from public, anon, authenticated;
