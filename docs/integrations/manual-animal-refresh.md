# Manual linked animal refresh

The Flutter control is shared by My Animals and Enter Show. There are no automatic herd pulls on screen load. The server verifies the signed-in user and household access; support impersonation cannot refresh. Status queries do not pull animals.

## Rollout

1. Deploy the additive animal_sync_requests/state migration after the existing HerdMaster partner API and token-rotation migrations. Preserve existing connection records. Do not replay historical migrations blindly; existing source filenames may differ from production migration history.
2. Deploy the Breeder show-connection patch with authenticated show_status and confirmed connection_id/last_refreshed_at responses. Its existing connect/save/disconnect/pull behavior remains available.
3. Deploy animal-sync with custom authentication (verify_jwt=false), then the updated herdmaster-api accepting optional completion metadata. Existing push requests omit both metadata fields and retain their behavior.
4. Deploy the Flutter app. Verify linked/unlinked users, authorized households, provider disconnection, failures, narrow-screen layout, and shared successful timestamps.
5. HerdMaster remains unavailable for manual refresh until Joe supplies HERDMASTER_ANIMAL_SYNC_URL (HTTPS) and HERDMASTER_ANIMAL_SYNC_SECRET. Set these as server secrets only after agreeing the callback contract in the OpenAPI webhooks section and passing a partner test. Never embed partner secrets or user credentials in Flutter.

## Provider adapters

The client consumes generic key/name/can_refresh/last_refreshed_at records. Each future integration needs an adapter in animal-sync which discovers only authorized linked accounts, invokes its real refresh route, and verifies completion. Do not infer account linkage from imported animal rows or email matching. Keep adapters server-side and reuse the provider-agnostic request/state tables and shared UI. The current adapters are RingMaster Breeder and HerdMaster; unknown providers cannot be refreshed until registered.

Last refreshed is completion of a whole requested sync, not opening a screen, renewing a token, receiving a webhook, or accepting a partial batch. Store timestamps per provider connection; never overwrite a successful time on failure. No periodic polling is installed.

HerdMaster callbacks are synchronous and bounded to 45 seconds; requested batches expire after two minutes. The completion SQL serializes writes, validates the live connection, prevents cross-account completion and rejects late/replayed delivery. Explicit inactive records are required; omitted animals remain unchanged. The schema is service-only with RLS, and clients cannot claim successful completion or forge its timestamp.

## Costs

Opening each panel makes one Show status Edge Function invocation plus a Breeder status invocation. A refresh uses a Show orchestration invocation per ready provider, provider status validation, the provider callback/pull, any partner animal batch invocations and optional token renewal, then one shared status reload. No fixed 1–2 total invocation guarantee is made. No background animal polling is created.
