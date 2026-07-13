import {
  assertCanManageShowSettings,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  obtainSquareToken,
  publicMerchant,
  squareEnv,
  squareGet,
  squareScopes,
  usableLocations,
} from "../_shared/square.ts";
import { encryptToken, sha256 } from "../_shared/token_crypto.ts";

function appRedirect(
  showId: string,
  result: string,
  message?: string,
): Response {
  const appUrl = squareEnv("RINGMASTER_APP_URL").replace(/\/$/, "");
  const parameters = new URLSearchParams({ showId, square: result });
  if (message) parameters.set("message", message.slice(0, 300));
  return Response.redirect(
    `${appUrl}/#/square-connect?${parameters.toString()}`,
    302,
  );
}

Deno.serve(async (request: Request) => {
  const callback = new URL(request.url);
  const state = callback.searchParams.get("state")?.trim() ?? "";
  const code = callback.searchParams.get("code")?.trim() ?? "";
  const oauthError = callback.searchParams.get("error_description") ??
    callback.searchParams.get("error");
  const admin = serviceClient();
  let showId = "";

  try {
    if (!state) {
      throw new Error("The Square callback did not include OAuth state.");
    }
    const stateHash = await sha256(state);
    const { data: stateRow, error: stateError } = await admin
      .from("payment_provider_oauth_states")
      .select("id,show_id,user_id,expires_at,consumed_at")
      .eq("provider", "square")
      .eq("state_hash", stateHash)
      .maybeSingle();
    if (stateError || !stateRow) {
      throw new Error("The Square connection request is invalid.");
    }
    showId = String(stateRow.show_id);
    if (stateRow.consumed_at) {
      throw new Error("This Square connection request was already used.");
    }
    if (new Date(stateRow.expires_at).getTime() <= Date.now()) {
      throw new Error(
        "The Square connection request expired. Please try again.",
      );
    }
    await assertCanManageShowSettings(
      admin,
      showId,
      String(stateRow.user_id),
    );

    const { data: consumedState, error: consumeError } = await admin
      .from("payment_provider_oauth_states")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", stateRow.id)
      .is("consumed_at", null)
      .select("id")
      .maybeSingle();
    if (consumeError || !consumedState) {
      throw new Error("The Square connection request could not be completed.");
    }
    if (oauthError) throw new Error(oauthError);
    if (!code) throw new Error("Square did not return an authorization code.");

    const token = await obtainSquareToken({
      grant_type: "authorization_code",
      code,
      redirect_uri: squareEnv("SQUARE_REDIRECT_URI"),
    });
    const accessToken = String(token.access_token ?? "");
    const refreshToken = String(token.refresh_token ?? "");
    const merchantId = String(token.merchant_id ?? "");
    const expiresAt = String(token.expires_at ?? "");
    if (!accessToken || !refreshToken || !merchantId || !expiresAt) {
      throw new Error("Square returned an incomplete authorization response.");
    }

    const [merchantResponse, locationsResponse] = await Promise.all([
      squareGet(`/v2/merchants/${encodeURIComponent(merchantId)}`, accessToken),
      squareGet("/v2/locations", accessToken),
    ]);
    const merchant = publicMerchant(merchantResponse);
    const locations = usableLocations(locationsResponse);
    const selectedLocation = locations.length === 1 ? locations[0] : null;
    const status = selectedLocation ? "ready" : "location_required";
    const now = new Date().toISOString();
    const metadata = {
      merchant,
      locations,
      selected_location_name: selectedLocation?.name ?? null,
      scopes: squareScopes,
    };

    const linkValues = {
      show_id: showId,
      provider: "square",
      provider_account_id: merchantId,
      provider_location_id: selectedLocation?.id ?? null,
      status,
      account_status: status,
      authorization_expires_at: expiresAt,
      metadata,
      updated_at: now,
    };
    const linkResult = await admin.from("show_payment_account_links").upsert(
      linkValues,
      { onConflict: "show_id,provider" },
    ).select("id").single();
    if (linkResult.error || !linkResult.data) {
      throw new Error("Unable to save the Square connection.");
    }

    const { error: credentialError } = await admin.from(
      "payment_provider_credentials",
    ).upsert(
      {
        payment_account_link_id: linkResult.data.id,
        provider: "square",
        access_token_encrypted: await encryptToken(accessToken),
        refresh_token_encrypted: await encryptToken(refreshToken),
        token_expires_at: expiresAt,
        updated_at: now,
      },
      { onConflict: "payment_account_link_id,provider" },
    );
    if (credentialError) {
      await admin.from("show_payment_account_links").update({
        status: "reconnect_required",
        account_status: "credential_storage_failed",
        updated_at: new Date().toISOString(),
      }).eq("id", linkResult.data.id);
      throw new Error(
        "Square connected, but its credentials could not be secured. Please reconnect.",
      );
    }

    return appRedirect(
      showId,
      selectedLocation ? "success" : "location_required",
    );
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Square connection failed.";
    return appRedirect(showId, "error", message);
  }
});
