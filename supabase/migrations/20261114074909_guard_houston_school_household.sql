-- Cart ownership alone must never authorize disclosure of an exhibitor name
-- or school record referenced by a malformed/legacy cart item.
create function show_registration_private.assert_youth_household(p_cart public.entry_carts)
returns void language plpgsql set search_path='' as $$
begin
  if exists(select 1 from show_registration_private.youth_exhibitors(p_cart.id) y
    left join public.exhibitors e on e.id=y.exhibitor_id
    where e.owner_user_id is distinct from p_cart.user_id) then
    raise exception 'Youth exhibitors must belong to this cart household.' using errcode='42501';
  end if;
end; $$;
revoke all on function show_registration_private.assert_youth_household(public.entry_carts) from public,anon,authenticated;

do $$declare sig text; d text; marker text; begin
  foreach sig in array array[
    'show_registration_private.requirements(uuid)',
    'show_registration_private.save_requirements(uuid,text,boolean,jsonb)',
    'show_registration_private.validate_cart(uuid)'
  ] loop
    d:=pg_get_functiondef(sig::regprocedure);
    marker:=case when sig='show_registration_private.requirements(uuid)'
      then 'if not found then return jsonb_build_object(''required'',false); end if;'
      else 'if not found then return; end if;' end;
    if (length(d)-length(replace(d,marker,'')))/length(marker)<>1 then raise exception 'School policy guard anchor changed: %',sig; end if;
    execute replace(d,marker,marker||E'\n  perform show_registration_private.assert_youth_household(c);');
  end loop;
end; $$;
