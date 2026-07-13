import { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  normalizeSquareScopes,
  obtainSquareToken,
  requiredSquarePaymentScopes,
  squareGet,
  usableLocations,
} from "./square.ts";
import { decryptToken, encryptToken } from "./token_crypto.ts";

export type SquareAuthorization = {
  linkId: string;
  merchantId: string;
  locationId: string;
  currency: string;
  accessToken: string;
};

export async function loadSquareAuthorization(
  client: SupabaseClient,
  showId: string,
): Promise<SquareAuthorization> {
  const { data: link, error: linkError } = await client
    .from("show_payment_account_links")
    .select("id,provider_account_id,provider_location_id,status")
    .eq("show_id", showId).eq("provider", "square").maybeSingle();
  if (linkError || !link || !link.provider_account_id ||
      !link.provider_location_id ||
      !["ready", "connected", "active"].includes(String(link.status))) {
    throw new Error("This show's Square account is not ready for payments.");
  }

  const { data: credential, error: credentialError } = await client
    .from("payment_provider_credentials")
    .select("id,access_token_encrypted,refresh_token_encrypted,granted_scopes,token_expires_at,credential_metadata")
    .eq("payment_account_link_id", link.id).eq("provider", "square")
    .maybeSingle();
  if (credentialError || !credential) {
    throw new Error("This show's Square authorization must be reconnected.");
  }

  const scopes = normalizeSquareScopes(credential.granted_scopes);
  if (!requiredSquarePaymentScopes.every((scope) => scopes.includes(scope))) {
    throw new Error(
      "Square must be reconnected to authorize RingMaster application fees.",
    );
  }

  let accessToken = await decryptToken(String(credential.access_token_encrypted));
  const expiry = Date.parse(String(credential.token_expires_at ?? ""));
  if (!Number.isFinite(expiry) || expiry <= Date.now() + 24 * 60 * 60 * 1000) {
    const refreshToken = await decryptToken(String(credential.refresh_token_encrypted));
    const refreshed = await obtainSquareToken({
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    });
    accessToken = String(refreshed.access_token ?? "");
    const nextRefreshToken = String(refreshed.refresh_token ?? refreshToken);
    const expiresAt = String(refreshed.expires_at ?? "");
    if (!accessToken || !expiresAt) {
      throw new Error("Square authorization could not be refreshed.");
    }
    const refreshedScopes = normalizeSquareScopes(refreshed.scopes ?? refreshed.scope);
    if (refreshedScopes.length > 0 &&
        !requiredSquarePaymentScopes.every((scope) => refreshedScopes.includes(scope))) {
      throw new Error("Square authorization no longer has the required payment scopes.");
    }
    const metadata = credential.credential_metadata &&
        typeof credential.credential_metadata === "object"
      ? credential.credential_metadata as Record<string, unknown>
      : {};
    const values: Record<string, unknown> = {
      access_token_encrypted: await encryptToken(accessToken),
      refresh_token_encrypted: await encryptToken(nextRefreshToken),
      token_expires_at: expiresAt,
      credential_metadata: {
        ...metadata,
        token_type: String(refreshed.token_type ?? "bearer"),
        short_lived: refreshed.short_lived === true,
        refresh_token_expires_at: refreshed.refresh_token_expires_at ??
          metadata.refresh_token_expires_at ?? null,
      },
      updated_at: new Date().toISOString(),
    };
    if (refreshedScopes.length > 0) values.granted_scopes = refreshedScopes;
    const { error } = await client.from("payment_provider_credentials")
      .update(values).eq("id", credential.id);
    if (error) throw new Error("Refreshed Square credentials could not be secured.");
  }

  const locations = usableLocations(await squareGet("/v2/locations", accessToken));
  const location = locations.find((item) => item.id === link.provider_location_id);
  const merchantId = String(link.provider_account_id);
  if (!location || (location.merchantId && location.merchantId !== merchantId)) {
    throw new Error("The selected Square location does not belong to this merchant.");
  }
  if (!location.currency) throw new Error("Square did not return a location currency.");

  return {
    linkId: String(link.id),
    merchantId,
    locationId: String(location.id),
    currency: location.currency,
    accessToken,
  };
}
