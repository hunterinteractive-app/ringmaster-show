# Square OAuth setup

This implementation connects a Square seller and selects a location. It does not create checkout payments.

## Database and functions

Apply `supabase/migrations/202607130001_square_oauth_state.sql`, then deploy:

- `square-connect-start`
- `square-connect-callback` with JWT verification disabled (configured in `supabase/config.toml`)
- `square-connect-status`
- `square-connect-select-location`
- `square-disconnect`

All functions except the public OAuth callback require a valid Supabase user JWT and verify `user_can_manage_show_settings`.

## Required Supabase secrets

```text
SQUARE_APPLICATION_ID=<Square sandbox or production application ID>
SQUARE_APPLICATION_SECRET=<matching Square application secret>
SQUARE_ENVIRONMENT=sandbox
SQUARE_REDIRECT_URI=https://yzjoycrvqkyfrksmaixf.supabase.co/functions/v1/square-connect-callback
PAYMENT_TOKEN_ENCRYPTION_KEY=<base64url-encoded 32 random bytes>
RINGMASTER_APP_URL=https://<RingMaster deployed web origin>
```

Optional:

```text
SQUARE_API_VERSION=2026-05-20
```

Generate the encryption key once and retain it in the Supabase secrets store. Rotating it requires re-encrypting existing credentials or reconnecting affected Square accounts.

For production, use the production application credentials and set `SQUARE_ENVIRONMENT=production`. Never mix sandbox credentials with production URLs.

## Square Developer Dashboard

In the matching Square application, open **OAuth**, and configure this exact redirect URL:

```text
https://yzjoycrvqkyfrksmaixf.supabase.co/functions/v1/square-connect-callback
```

The value must exactly match `SQUARE_REDIRECT_URI`. The Flutter return route is handled separately by the callback using:

```text
https://<RingMaster deployed web origin>/#/square-connect
```

The authorization request asks only for:

- `MERCHANT_PROFILE_READ` for merchant identity and locations.
- `PAYMENTS_WRITE` for future payment creation and refunds.

## Sandbox test checklist

1. Apply the migration, set sandbox secrets, and deploy all five functions.
2. Sign in as a user with show-settings permission and open **Show Fees & Payments**.
3. Confirm **Connect Square** is disabled for support-mode impersonation and locked/finalized shows.
4. Connect a Square sandbox seller and approve the two requested scopes.
5. Confirm the callback returns to `/#/square-connect`, reopens the correct show, and never places OAuth tokens in the URL.
6. For a seller with one active location, confirm status becomes **Ready** automatically.
7. For a seller with multiple active locations, confirm status is **Location selection required**, select one, and verify status becomes **Ready**.
8. Confirm the Square enable toggle stays disabled until `get_show_checkout_options` reports Square ready.
9. Refresh status and confirm merchant, location, scopes, and expiry are returned without any token values.
10. Test an expired/revoked authorization and confirm **Authorization expired** or **Reconnect required** appears.
11. Disconnect Square, confirm its credentials are removed/invalidated, `square_enabled` becomes false, and Stripe/PayPal records are unchanged.
12. When Square was the default provider, verify the only other enabled-ready provider becomes default; otherwise verify the default is cleared.
13. Attempt start/status/location/disconnect as an unauthorized user and confirm each request is rejected.
14. Attempt to reuse or wait more than 10 minutes before using an OAuth state and confirm the callback rejects it.
