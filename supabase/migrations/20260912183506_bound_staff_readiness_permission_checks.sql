-- Keep the canonical validator and table RLS unchanged. Check staff access
-- once before running its whole-section aggregate, rather than per entry.
-- The privileged implementation lives outside the exposed Data API schema.
create function judging_private.get_section_readiness(p_show_id uuid, p_section_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role' and (
    auth.uid() is null or (
      not coalesce(public.user_can_enter_results(p_show_id), false)
      and not coalesce(public.user_can_manage_entries(p_show_id), false)
      and not coalesce(public.user_can_manage_show_settings(p_show_id), false)
    )
  ) then
    raise exception 'You do not have access to this show' using errcode = '42501';
  end if;
  if p_section_id is null or not exists (
    select 1 from public.show_sections where id=p_section_id and show_id=p_show_id
  ) then
    raise exception 'A section belonging to this show is required' using errcode = '22023';
  end if;
  return public.show_results_readiness_scoped(p_show_id, array[p_section_id]);
end;
$$;
revoke all on function judging_private.get_section_readiness(uuid,uuid) from public, anon;
grant execute on function judging_private.get_section_readiness(uuid,uuid) to authenticated, service_role;

create function public.get_judging_section_readiness(p_show_id uuid, p_section_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select judging_private.get_section_readiness(p_show_id, p_section_id);
$$;
revoke all on function public.get_judging_section_readiness(uuid,uuid) from public, anon;
grant execute on function public.get_judging_section_readiness(uuid,uuid) to authenticated, service_role;
notify pgrst, 'reload schema';
