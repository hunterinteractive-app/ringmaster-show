import { assertHouseholdAccess } from "../_shared/household.ts";
import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { loadSquareAuthorization } from "../_shared/square_credentials.ts";
import { cancelUnpaidSquareLink } from "../_shared/square_checkout_cancellation.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  try {
    const { client: actorClient } = await authenticatedUser(request);
    const body = await request.json() as {
      cart_id?: string;
      payment_session_id?: string;
    };
    const cartId = body.cart_id?.trim() ?? "";
    const sessionId = body.payment_session_id?.trim() ?? "";
    if (!cartId || !sessionId) {
      throw new Error("Cart and payment session are required.");
    }
    const admin = serviceClient();
    const { data: cart, error } = await admin.from("entry_carts")
      .select(
        "id,user_id,show_id,status,payment_status,active_payment_session_id,completed_payment_session_id",
      )
      .eq("id", cartId).maybeSingle();
    if (error || !cart) throw new Error("Cart not found.");
    await assertHouseholdAccess(actorClient, String(cart.user_id));
    if (
      cart.status !== "active" || cart.completed_payment_session_id ||
      ["paid", "refunded"].includes(String(cart.payment_status))
    ) {
      throw new Error(
        "This cart has already been submitted or paid and cannot be edited.",
      );
    }
    if (cart.active_payment_session_id !== sessionId) {
      throw new Error("The checkout changed. Refresh your cart and try again.");
    }
    const { data: attempt, error: attemptError } = await admin.from(
      "show_payment_sessions",
    )
      .select(
        "id,provider_order_id,provider_session_id,attempt_status,provider_payment_id",
      )
      .eq("id", sessionId).eq("cart_id", cartId).eq("provider", "square")
      .maybeSingle();
    if (
      attemptError || !attempt || attempt.provider_payment_id ||
      !["created", "pending", "processing"].includes(
        String(attempt.attempt_status),
      )
    ) {
      throw new Error(
        "This checkout cannot be canceled. Check its payment status first.",
      );
    }
    const authorization = await loadSquareAuthorization(
      admin,
      String(cart.show_id),
      { requireReady: false },
    );
    await cancelUnpaidSquareLink(
      String(attempt.provider_order_id ?? ""),
      String(attempt.provider_session_id ?? ""),
      authorization.accessToken,
    );
    const { data: result, error: finishError } = await admin.rpc(
      "finish_cancelled_square_checkout",
      {
        p_cart_id: cartId,
        p_payment_session_id: sessionId,
      },
    );
    if (finishError) throw new Error(finishError.message);
    return jsonResponse(result);
  } catch (error) {
    return jsonResponse(
      { error: errorMessage(error) },
      errorMessage(error) === "Authentication required." ? 401 : 400,
    );
  }
});
