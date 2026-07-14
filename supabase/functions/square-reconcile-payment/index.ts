import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  assertCanManageShowSettings,
  authenticatedUser,
  isServiceRoleRequest,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  loadSquarePaymentAttempt,
  reconcileSquarePayment,
  retrieveSquarePaymentForAttempt,
} from "../_shared/square_payment_reconciler.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await request.json() as {
      payment_session_id?: string;
      provider_payment_id?: string;
    };
    const paymentSessionId = body.payment_session_id?.trim() ?? "";
    const providerPaymentId = body.provider_payment_id?.trim() || null;
    if (!paymentSessionId) {
      return jsonResponse({ error: "payment_session_id is required." }, 400);
    }

    const admin = serviceClient();
    const attempt = await loadSquarePaymentAttempt(admin, paymentSessionId);
    if (!await isServiceRoleRequest(request)) {
      const { user, client } = await authenticatedUser(request);
      await assertCanManageShowSettings(client, attempt.show_id, user.id);
    }

    const lookup = await retrieveSquarePaymentForAttempt(
      admin,
      attempt,
      providerPaymentId,
    );
    if (!lookup) {
      throw new Error("No Square payment was found for the saved order.");
    }
    const result = await reconcileSquarePayment(admin, {
      attempt,
      payment: lookup.payment,
      authorization: lookup.authorization,
      requireCompleted: true,
    });
    const { data: session, error: sessionError } = await admin
      .from("show_payment_sessions")
      .select(
        "id,cart_id,provider,provider_order_id,provider_payment_id,attempt_status,status",
      )
      .eq("id", paymentSessionId).single();
    const { data: cart, error: cartError } = await admin.from("entry_carts")
      .select(
        "id,status,payment_status,active_payment_session_id,completed_payment_session_id",
      )
      .eq("id", attempt.cart_id).single();
    if (sessionError || cartError || !session || !cart) {
      throw new Error("Finalized payment status could not be loaded.");
    }
    return jsonResponse({
      reconciled: result.processed,
      finalized: session.attempt_status === "finalized" &&
        cart.completed_payment_session_id === session.id,
      already_finalized: result.alreadyFinalized,
      payment_status: result.paymentStatus,
      session,
      cart,
    });
  } catch (error) {
    const message = errorMessage(error);
    const status = message === "Authentication required."
      ? 401
      : message.includes("permission")
      ? 403
      : 400;
    return jsonResponse({ error: message }, status);
  }
});
