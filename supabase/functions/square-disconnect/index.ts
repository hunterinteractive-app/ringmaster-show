import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  assertCanManageShowSettings,
  assertShowUnlocked,
  authenticatedUser,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  squareApiVersion,
  squareConnectBase,
  squareEnv,
} from "../_shared/square.ts";
import { decryptToken } from "../_shared/token_crypto.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

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
    await assertShowUnlocked(admin, showId);

    const { data: link, error: linkError } = await admin.from(
      "show_payment_account_links",
    )
      .select("id").eq("show_id", showId).eq("provider", "square")
      .maybeSingle();
    if (linkError) throw new Error("Unable to load the Square connection.");

    if (link) {
      const { data: credential } = await admin.from(
        "payment_provider_credentials",
      )
        .select("access_token_encrypted")
        .eq("payment_account_link_id", link.id).eq("provider", "square")
        .maybeSingle();
      if (credential?.access_token_encrypted) {
        try {
          const accessToken = await decryptToken(
            String(credential.access_token_encrypted),
          );
          await fetch(`${squareConnectBase}/oauth2/revoke`, {
            method: "POST",
            headers: {
              Authorization: `Client ${squareEnv("SQUARE_APPLICATION_SECRET")}`,
              "Content-Type": "application/json",
              "Square-Version": squareApiVersion,
            },
            body: JSON.stringify({
              client_id: squareEnv("SQUARE_APPLICATION_ID"),
              access_token: accessToken,
            }),
          });
        } catch (_) {
          // Local invalidation still proceeds when Square is unavailable or the token is already invalid.
        }
      }
      await admin.from("payment_provider_credentials").delete()
        .eq("payment_account_link_id", link.id).eq("provider", "square");
      const { error: disconnectError } = await admin.from(
        "show_payment_account_links",
      ).update({
        provider_account_id: null,
        provider_location_id: null,
        status: "not_connected",
        account_status: "disconnected",
        authorization_expires_at: null,
        metadata: {},
        updated_at: new Date().toISOString(),
      }).eq("id", link.id);
      if (disconnectError) throw new Error("Unable to disconnect Square.");
    }

    const { data: settings, error: settingsError } = await admin.from(
      "show_payment_settings",
    )
      .select("stripe_enabled,paypal_enabled,default_online_provider")
      .eq("show_id", showId).maybeSingle();
    if (settingsError) {
      throw new Error("Unable to update payment configuration.");
    }

    let defaultProvider = settings?.default_online_provider ?? null;
    if (defaultProvider === "square") {
      const candidateProviders = [
        ifEnabled(settings?.stripe_enabled, "stripe"),
        ifEnabled(settings?.paypal_enabled, "paypal"),
      ].filter((provider): provider is string => provider !== null);
      const { data: readyLinks, error: readyError } = candidateProviders.length
        ? await admin.from("show_payment_account_links").select(
          "provider,status",
        )
          .eq("show_id", showId).in("provider", candidateProviders).eq(
            "status",
            "ready",
          )
        : { data: [], error: null };
      if (readyError) {
        throw new Error("Unable to choose a replacement payment provider.");
      }
      const readyProviders = (readyLinks ?? []).map((row) =>
        String(row.provider)
      );
      defaultProvider = readyProviders.length === 1 ? readyProviders[0] : null;
    }

    const { error: updateSettingsError } = await admin.from(
      "show_payment_settings",
    ).update({
      square_enabled: false,
      default_online_provider: defaultProvider,
      updated_at: new Date().toISOString(),
    }).eq("show_id", showId);
    if (updateSettingsError) {
      throw new Error("Unable to disable Square for this show.");
    }
    return jsonResponse({
      disconnected: true,
      default_online_provider: defaultProvider,
    });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});

function ifEnabled(enabled: unknown, provider: string): string | null {
  return enabled === true ? provider : null;
}
