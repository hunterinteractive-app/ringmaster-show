update public.payment_provider_credentials
set granted_scopes = array['MERCHANT_PROFILE_READ', 'PAYMENTS_WRITE']::text[],
    updated_at = now()
where provider = 'square'
  and granted_scopes is null;
