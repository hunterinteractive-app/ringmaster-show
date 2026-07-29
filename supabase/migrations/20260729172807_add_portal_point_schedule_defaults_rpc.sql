create function public.get_sweepstakes_portal_point_defaults(p_portal_club_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.can_preview_sweepstakes_portal_club(p_portal_club_id) then
    raise exception 'Not authorized to view this club point schedule';
  end if;

  return jsonb_build_object(
    'placements', coalesce((
      select jsonb_agg(jsonb_build_object('place', place_number, 'points', place_points) order by place_number)
      from public.point_place_scale
    ), '[]'::jsonb),
    'awards', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', award_code,
        'source_type', source_type::text,
        'rabbit_points', award_points,
        'cavy_points', cavy_award_points,
        'active', is_active
      ) order by sort_order)
      from public.point_award_scale
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_sweepstakes_portal_point_defaults(uuid) from public;
grant execute on function public.get_sweepstakes_portal_point_defaults(uuid) to authenticated;
