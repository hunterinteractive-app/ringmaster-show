import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  assertCanManageShowSettings,
  authenticatedUser,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  obtainSquareToken,
  publicMerchant,
  squareGet,
  tokenStatus,
  usableLocations,
} from "../_shared/square.ts";
import { decryptToken, encryptToken } from "../_shared/token_crypto.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  let linkId = "";
  let knownExpiry = "";
  try {
    const { show_id: showId = "" } = await request.json() as {
      show_id?: string;
    };
    if (!showId.trim()) {
      return jsonResponse({ error: "show_id is required." }, 400);
    }
    const { user, client } = await authenticatedUser(request);
    await assertCanManageShowSettings(client, showId, user.id);
    const admin = serviceClient();

    const { data: link, error: linkError } = await admin
      .from("show_payment_account_links")
      .select(
        "id,provider_account_id,provider_location_id,status,account_status,authorization_expires_at,metadata",
      )
      .eq("show_id", showId).eq("provider", "square").maybeSingle();
    if (linkError) throw new Error("Unable to load Square status.");
    if (!link) {
      return jsonResponse({
        connected: false,
        ready: false,
        status: "not_connected",
        reconnect_required: false,
        available_locations: [],
        scopes: [],
      });
    }
    linkId = String(link.id);
    knownExpiry = String(link.authorization_expires_at ?? "");

    const { data: credential, error: credentialError } = await admin
      .from("payment_provider_credentials")
      .select(
        "id,access_token_encrypted,refresh_token_encrypted,token_expires_at",
      )
      .eq("payment_account_link_id", link.id).eq("provider", "square")
      .maybeSingle();
    if (credentialError || !credential) {
      await admin.from("show_payment_account_links").update({
        status: "reconnect_required",
        account_status: "credentials_missing",
        updated_at: new Date().toISOString(),
      }).eq("id", link.id);
      return jsonResponse({
        connected: true,
        ready: false,
        status: "reconnect_required",
        reconnect_required: true,
      });
    }

    let accessToken = await decryptToken(
      String(credential.access_token_encrypted),
    );
    let expiresAt = String(
      credential.token_expires_at ?? link.authorization_expires_at ?? "",
    );
    const refreshNeeded = !expiresAt ||
      new Date(expiresAt).getTime() <= Date.now() + 24 * 60 * 60 * 1000;
    if (refreshNeeded) {
      const refreshToken = await decryptToken(
        String(credential.refresh_token_encrypted),
      );
      const refreshed = await obtainSquareToken({
        grant_type: "refresh_token",
        refresh_token: refreshToken,
      });
      accessToken = String(refreshed.access_token ?? "");
      expiresAt = String(refreshed.expires_at ?? "");
      const nextRefreshToken = String(refreshed.refresh_token ?? refreshToken);
      if (!accessToken || !expiresAt) {
        throw new Error("Square authorization could not be refreshed.");
      }
      const { error: refreshSaveError } = await admin.from(
        "payment_provider_credentials",
      ).update({
        access_token_encrypted: await encryptToken(accessToken),
        refresh_token_encrypted: await encryptToken(nextRefreshToken),
        token_expires_at: expiresAt,
        updated_at: new Date().toISOString(),
      }).eq("id", credential.id);
      if (refreshSaveError) {
        throw new Error("Refreshed Square credentials could not be secured.");
      }
    }

    const [authorization, merchantResponse, locationsResponse] = await Promise
      .all([
        tokenStatus(accessToken),
        squareGet("/v2/merchants/me", accessToken),
        squareGet("/v2/locations", accessToken),
      ]);
    const merchant = publicMerchant(merchantResponse);
    const locations = usableLocations(locationsResponse);
    const selectedLocationId = String(link.provider_location_id ?? "");
    const selectedLocation = locations.find((location) =>
      location.id === selectedLocationId
    ) ?? null;
    const merchantId = String(merchant.id || link.provider_account_id || "");
    const scopes = Array.isArray(authorization.scopes)
      ? authorization.scopes.map(String)
      : [];
    const ready = Boolean(merchantId && selectedLocation);
    const status = ready ? "ready" : "location_required";
    const metadata = {
      merchant,
      locations,
      selected_location_name: selectedLocation?.name ?? null,
      scopes,
    };
    const { error: updateError } = await admin.from(
      "show_payment_account_links",
    ).update({
      provider_account_id: merchantId,
      provider_location_id: selectedLocation?.id ?? null,
      status,
      account_status: status,
      authorization_expires_at: expiresAt,
      metadata,
      updated_at: new Date().toISOString(),
    }).eq("id", link.id);
    if (updateError) throw new Error("Unable to update Square status.");

    return jsonResponse({
      connected: true,
      ready,
      status,
      merchant_id: merchantId,
      merchant_name: String(merchant.business_name ?? ""),
      selected_location_id: selectedLocation?.id ?? null,
      selected_location_name: selectedLocation?.name ?? null,
      available_locations: locations,
      scopes,
      expiry: expiresAt,
      reconnect_required: false,
    });
  } catch (error) {
    const expired = knownExpiry.length > 0 &&
      new Date(knownExpiry).getTime() <= Date.now();
    const failureStatus = expired
      ? "authorization_expired"
      : "reconnect_required";
    if (linkId) {
      await serviceClient().from("show_payment_account_links").update({
        status: failureStatus,
        account_status: "authorization_invalid",
        updated_at: new Date().toISOString(),
      }).eq("id", linkId);
    }
    return jsonResponse({
      error: errorMessage(error),
      connected: Boolean(linkId),
      ready: false,
      status: failureStatus,
      reconnect_required: true,
    }, 400);
  }
});
