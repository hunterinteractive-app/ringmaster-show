import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  assertCanManageShowSettings,
  assertShowUnlocked,
  authenticatedUser,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  normalizeSquareScopes,
  requiredSquarePaymentScopes,
} from "../_shared/square.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await request.json() as {
      show_id?: string;
      location_id?: string;
    };
    const showId = body.show_id?.trim() ?? "";
    const locationId = body.location_id?.trim() ?? "";
    if (!showId || !locationId) {
      return jsonResponse(
        { error: "show_id and location_id are required." },
        400,
      );
    }

    const { user, client } = await authenticatedUser(request);
    await assertCanManageShowSettings(client, showId, user.id);
    const admin = serviceClient();
    await assertShowUnlocked(admin, showId);
    const { data: link, error } = await admin.from("show_payment_account_links")
      .select("id,provider_account_id,metadata")
      .eq("show_id", showId).eq("provider", "square").maybeSingle();
    if (error || !link) {
      throw new Error("Square is not connected for this show.");
    }

    const metadata = link.metadata && typeof link.metadata === "object"
      ? link.metadata as Record<string, unknown>
      : {};
    const locations = Array.isArray(metadata.locations)
      ? metadata.locations
      : [];
    const selected = locations.find((raw) => {
      if (!raw || typeof raw !== "object") return false;
      const location = raw as Record<string, unknown>;
      return String(location.id ?? "") === locationId &&
        String(location.status ?? "") === "ACTIVE";
    }) as Record<string, unknown> | undefined;
    if (!selected) {
      throw new Error("Select an active location returned by Square.");
    }
    if (!String(link.provider_account_id ?? "")) {
      throw new Error("Square merchant identity is missing. Reconnect Square.");
    }
    const { data: credential, error: credentialError } = await admin
      .from("payment_provider_credentials")
      .select("granted_scopes")
      .eq("payment_account_link_id", link.id)
      .eq("provider", "square")
      .maybeSingle();
    const grantedScopes = normalizeSquareScopes(credential?.granted_scopes);
    if (credentialError || !credential ||
      !requiredSquarePaymentScopes.every((scope) =>
        grantedScopes.includes(scope)
      )) {
      throw new Error(
        "Reconnect Square to authorize RingMaster application fees.",
      );
    }

    const { error: updateError } = await admin.from(
      "show_payment_account_links",
    ).update({
      provider_location_id: locationId,
      status: "ready",
      account_status: "ready",
      metadata: {
        ...metadata,
        selected_location_name: String(selected.name ?? "Square location"),
      },
      updated_at: new Date().toISOString(),
    }).eq("id", link.id);
    if (updateError) throw new Error("Unable to save the Square location.");
    return jsonResponse({
      ready: true,
      location_id: locationId,
      location_name: selected.name,
    });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});
