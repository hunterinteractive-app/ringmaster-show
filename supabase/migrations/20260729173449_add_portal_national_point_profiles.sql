create or replace function public.get_sweepstakes_portal_point_defaults(p_portal_club_id uuid)
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
    'placements', coalesce((select jsonb_agg(jsonb_build_object('place', place_number, 'points', place_points) order by place_number) from public.point_place_scale), '[]'::jsonb),
    'awards', coalesce((select jsonb_agg(jsonb_build_object('code', award_code, 'source_type', source_type::text, 'rabbit_points', award_points, 'cavy_points', cavy_award_points, 'active', is_active) order by sort_order) from public.point_award_scale), '[]'::jsonb),
    'national_profiles', coalesce((
      select jsonb_agg(profile order by profile ->> 'breed_name')
      from (
        select distinct on (lower(matrix.breed_name)) jsonb_build_object(
          'breed_name', matrix.breed_name,
          'class_points_model', matrix.class_points_model,
          'multiplier_type', matrix.multiplier_type,
          'placement_depth', matrix.placement_depth,
          'placements', jsonb_build_array(matrix.place_1, matrix.place_2, matrix.place_3, matrix.place_4, matrix.place_5),
          'bis_points', matrix.bis_points,
          'bris_points', matrix.bris_points,
          'bog_points', matrix.bog_points,
          'bob_points', matrix.bob_points,
          'participation_points', matrix.participation_points,
          'notes', coalesce(matrix.national_notes, matrix.specialty_notes, matrix.notes)
        ) as profile
        from public.show_sanctions sanction
        join public.sweepstakes_portal_clubs club on club.id = p_portal_club_id and club.normalized_name = lower(btrim(sanction.club_name))
        join public.breed_rules_matrix matrix on lower(matrix.breed_name) = lower(sanction.breed_name)
        where upper(btrim(sanction.sanctioning_body)) = 'NATIONAL CLUB'
          and (matrix.national_override or matrix.specialty_override)
        order by lower(matrix.breed_name), matrix.updated_at desc
      ) profiles
    ), '[]'::jsonb)
  );
end;
$$;
