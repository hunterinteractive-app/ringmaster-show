-- Public, token-scoped metadata for the Add Entry form. It intentionally
-- exposes only the verified exhibitor's show sections and prior entry values.
create or replace function public.get_exhibitor_checkin_add_entry_options(
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_settings public.show_checkin_settings%rowtype;
begin
  select * into v_session from public.show_checkin_sessions
  where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'), 'hex')
    and revoked_at is null and expires_at > now();
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501'; end if;

  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;
  if not found or not v_settings.is_enabled
     or coalesce(v_settings.entry_edit_permissions ->> 'add_entry', 'disabled') not in ('automatic', 'approval') then
    raise exception 'Adding entries is not available through this portal';
  end if;

  return jsonb_build_object(
    'permission', v_settings.entry_edit_permissions ->> 'add_entry',
    'sections', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'label', coalesce(nullif(s.display_name, ''), upper(s.letter))) order by s.sort_order)
      from public.show_sections s where s.show_id = v_session.show_id
    ), '[]'::jsonb),
    'defaults', coalesce((
      select jsonb_build_object('species', e.species, 'breed', e.breed, 'variety', e.variety, 'class', e.class_name, 'sex', e.sex)
      from public.entries e where e.show_id = v_session.show_id and e.exhibitor_id = v_session.exhibitor_id
      order by e.updated_at desc limit 1
    ), '{}'::jsonb)
  );
end;
$$;
revoke all on function public.get_exhibitor_checkin_add_entry_options(text) from public;
grant execute on function public.get_exhibitor_checkin_add_entry_options(text) to anon, authenticated, service_role;
