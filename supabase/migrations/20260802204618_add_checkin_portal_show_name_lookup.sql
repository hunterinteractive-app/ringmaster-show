-- This is intentionally limited to the show name. A valid, enabled QR token
-- may identify the show before an exhibitor verifies their identity, but it
-- must not reveal entries, exhibitor records, or any other show data.

create or replace function public.get_exhibitor_checkin_portal_show(
  p_portal_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_show public.shows%rowtype;
begin
  select s.* into v_show
  from public.show_checkin_settings settings
  join public.shows s on s.id = settings.show_id
  where settings.portal_token_hash = encode(
    extensions.digest(btrim(coalesce(p_portal_token, '')), 'sha256'),
    'hex'
  )
    and settings.is_enabled
    and (settings.opens_at is null or now() >= settings.opens_at)
    and (settings.closes_at is null or now() <= settings.closes_at);

  if not found then
    raise exception 'Check-in is not available';
  end if;

  return jsonb_build_object('show_name', v_show.name);
end;
$$;

revoke all on function public.get_exhibitor_checkin_portal_show(text) from public;
grant execute on function public.get_exhibitor_checkin_portal_show(text)
  to anon, authenticated, service_role;
