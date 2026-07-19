begin;

do $test$
declare
  v_first jsonb;
  v_repeat jsonb;
  v_duplicate jsonb;
  v_count integer;
  v_email text := 'purchase-email-test@example.invalid';
begin
  delete from public.license_purchase_email_events
  where normalized_secretary_email = v_email;

  v_first := public.claim_license_purchase_email(
    'stripe',
    'evt_license_email_first',
    'cs_license_email_first',
    '  Purchase-Email-Test@Example.Invalid ',
    null,
    'single_show',
    '2026-07-19T12:00:00Z'
  );

  if v_first ->> 'claimed' <> 'true'
     or v_first ->> 'email_type' <> 'welcome'
     or (v_first ->> 'purchase_count')::integer <> 1 then
    raise exception 'First purchase was not claimed as welcome: %', v_first;
  end if;

  v_repeat := public.claim_license_purchase_email(
    'stripe',
    'evt_license_email_repeat',
    'cs_license_email_repeat',
    v_email,
    null,
    'four_shows',
    '2026-07-19T13:00:00Z'
  );

  if v_repeat ->> 'claimed' <> 'true'
     or v_repeat ->> 'email_type' <> 'returning'
     or (v_repeat ->> 'purchase_count')::integer <> 2 then
    raise exception 'Repeat purchase was not classified as returning: %', v_repeat;
  end if;

  v_duplicate := public.claim_license_purchase_email(
    'stripe',
    'evt_license_email_repeat',
    'cs_license_email_repeat',
    v_email,
    null,
    'four_shows',
    '2026-07-19T13:00:00Z'
  );

  if v_duplicate ->> 'claimed' <> 'false' then
    raise exception 'Duplicate webhook was claimed twice: %', v_duplicate;
  end if;

  select count(*) into v_count
  from public.license_purchase_email_events
  where normalized_secretary_email = v_email;

  if v_count <> 2 then
    raise exception 'Duplicate webhook created an extra audit row: %', v_count;
  end if;
end;
$test$;

rollback;
