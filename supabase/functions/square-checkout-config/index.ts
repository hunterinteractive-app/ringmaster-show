import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { squareEnv, squareEnvironment } from "../_shared/square.ts";
import { loadSquareAuthorization } from "../_shared/square_credentials.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const { show_id: showId = "" } = await request.json() as { show_id?: string };
    if (!showId.trim()) return jsonResponse({ error: "show_id is required." }, 400);
    const { client } = await authenticatedUser(request);
    const { data: visibleShow, error: accessError } = await client.from("shows")
      .select("id").eq("id", showId).maybeSingle();
    if (accessError || !visibleShow) throw new Error("You do not have access to this checkout.");

    const { data: optionsData, error: optionsError } = await client.rpc(
      "get_show_checkout_options",
      { p_show_id: showId },
    );
    if (optionsError || !optionsData || typeof optionsData !== "object") {
      throw new Error("Unable to load checkout configuration.");
    }
    const checkout = optionsData as Record<string, unknown>;
    const providers = Array.isArray(checkout.providers) ? checkout.providers : [];
    const square = providers.find((item) => item && typeof item === "object" &&
      String((item as Record<string, unknown>).provider) === "square") as
      | Record<string, unknown> | undefined;
    if (checkout.allow_online !== true || square?.enabled !== true || square.ready !== true) {
      throw new Error("Square is not available for this show's checkout.");
    }

    const admin = serviceClient();
    const authorization = await loadSquareAuthorization(admin, showId);
    const { data: fees, error: feeError } = await admin.from("show_fee_settings")
      .select("currency").eq("show_id", showId).maybeSingle();
    if (feeError || !fees?.currency) throw new Error("Show currency is not configured.");
    const currency = String(fees.currency).toLowerCase();
    if (currency !== authorization.currency) {
      throw new Error("The show's currency does not match the selected Square location.");
    }

    return jsonResponse({
      application_id: squareEnv("SQUARE_APPLICATION_ID"),
      location_id: authorization.locationId,
      environment: squareEnvironment === "production" ? "production" : "sandbox",
      currency,
    });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) },
      errorMessage(error) === "Authentication required." ? 401 : 400);
  }
});
