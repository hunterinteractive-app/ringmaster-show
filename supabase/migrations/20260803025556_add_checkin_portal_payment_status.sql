-- Return the authoritative payment snapshot that belongs to the verified
-- exhibitor. This is display-only: the public portal does not create a cart
-- or payment attempt simply by loading the check-in page.
create or replace function public.get_exhibitor_checkin_portal_data(
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session public.show_checkin_sessions%rowtype;
  v_show public.shows%rowtype;
  v_exhibitor public.exhibitors%rowtype;
  v_settings public.show_checkin_settings%rowtype;
  v_record public.show_checkin_records%rowtype;
  v_entries jsonb;
  v_payment jsonb;
begin
  select * into v_session
  from public.show_checkin_sessions
  where session_token_hash = encode(
    extensions.digest(btrim(coalesce(p_session_token, '')), 'sha256'),
    'hex'
  )
    and revoked_at is null
    and expires_at > now()
  for update;

  if not found then
    raise exception 'Your check-in session has expired. Please verify again.'
      using errcode = '42501';
  end if;

  select * into v_show from public.shows where id = v_session.show_id;
  select * into v_exhibitor from public.exhibitors where id = v_session.exhibitor_id;
  select * into v_settings from public.show_checkin_settings where show_id = v_session.show_id;

  if not found or not v_settings.is_enabled
     or (v_settings.opens_at is not null and now() < v_settings.opens_at)
     or (v_settings.closes_at is not null and now() > v_settings.closes_at) then
    raise exception 'Check-in is not available';
  end if;

  insert into public.show_checkin_records(show_id, exhibitor_id, status)
  values (v_session.show_id, v_session.exhibitor_id, 'in_progress')
  on conflict (show_id, exhibitor_id) do nothing;

  select * into v_record
  from public.show_checkin_records
  where show_id = v_session.show_id and exhibitor_id = v_session.exhibitor_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'section_id', e.section_id,
    'show_letter', upper(sec.letter),
    'show_label', coalesce(
      nullif(sec.display_name, ''),
      initcap(coalesce(sec.kind::text, 'Show')) || ' ' || upper(coalesce(sec.letter, ''))
    ),
    'species', e.species,
    'tattoo', e.tattoo,
    'animal_name', e.animal_name,
    'breed', e.breed,
    'variety', e.variety,
    'fur_variety', e.fur_variety,
    'class_name', e.class_name,
    'sex', e.sex,
    'is_fur', e.is_fur,
    'status', e.status,
    'scratched_at', e.scratched_at
  ) order by sec.sort_order, e.breed, e.variety, e.class_name, e.sex, e.tattoo), '[]'::jsonb)
  into v_entries
  from public.entries e
  left join public.show_sections sec on sec.id = e.section_id
  where e.show_id = v_session.show_id
    and e.exhibitor_id = v_session.exhibitor_id;

  select jsonb_build_object(
    'balance_due_cents', greatest(coalesce(b.balance_due_cents, 0), 0),
    'currency', coalesce(nullif(lower(b.currency), ''), 'usd'),
    'payment_status', coalesce(nullif(b.payment_status, ''), 'unpaid'),
    'online_payment_available', coalesce(
      v_show.payment_timing_mode in ('online_only', 'online_or_at_show')
      and exists (
        select 1
        from public.show_payment_settings ps
        where ps.show_id = v_show.id
          and (
            (coalesce(ps.stripe_enabled, false) and exists (
              select 1 from public.show_payment_account_links l
              where l.show_id = v_show.id and l.provider = 'stripe'
                and coalesce(l.charges_enabled, false)
                and coalesce(l.account_status, '') = 'ready'
            ))
            or (coalesce(ps.square_enabled, false) and exists (
              select 1 from public.show_payment_account_links l
              where l.show_id = v_show.id and l.provider = 'square'
                and l.provider_account_id is not null and l.provider_location_id is not null
                and coalesce(l.status, '') in ('ready', 'connected', 'active')
            ))
            or (coalesce(ps.paypal_enabled, false) and exists (
              select 1 from public.show_payment_account_links l
              where l.show_id = v_show.id and l.provider = 'paypal'
                and l.provider_account_id is not null
                and coalesce(l.status, '') in ('ready', 'connected', 'active')
            ))
          )
      ), false)
  ) into v_payment
  from public.show_exhibitor_balances b
  where b.show_id = v_session.show_id
    and b.exhibitor_id = v_session.exhibitor_id
    and (
      b.source = 'entries'
      or not exists (
        select 1 from public.show_exhibitor_balances authoritative
        where authoritative.show_id = b.show_id
          and authoritative.exhibitor_id = b.exhibitor_id
          and authoritative.source = 'entries'
      )
    )
  order by case when b.source = 'entries' then 0 else 1 end, b.updated_at desc
  limit 1;

  v_payment := coalesce(v_payment, jsonb_build_object(
    'balance_due_cents', 0,
    'currency', 'usd',
    'payment_status', 'paid',
    'online_payment_available', false
  ));

  update public.show_checkin_sessions
  set last_seen_at = now()
  where id = v_session.id;

  return jsonb_build_object(
    'show', jsonb_build_object('id', v_show.id, 'name', v_show.name),
    'exhibitor', jsonb_build_object(
      'id', v_exhibitor.id,
      'number', v_exhibitor.exhibitor_number,
      'name', coalesce(nullif(v_exhibitor.display_name, ''), nullif(v_exhibitor.showing_name, ''), trim(coalesce(v_exhibitor.first_name, '') || ' ' || coalesce(v_exhibitor.last_name, '')))
    ),
    'checkin', jsonb_build_object(
      'status', v_record.status,
      'require_initials', v_settings.require_initials,
      'require_signature', v_settings.require_signature,
      'entry_edit_permissions', v_settings.entry_edit_permissions
    ),
    'payment', v_payment,
    'entries', v_entries,
    'expires_at', v_session.expires_at
  );
end;
$$;

revoke all on function public.get_exhibitor_checkin_portal_data(text) from public;
grant execute on function public.get_exhibitor_checkin_portal_data(text)
  to anon, authenticated, service_role;
