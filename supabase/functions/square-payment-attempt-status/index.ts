import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await request.json() as {
      cart_id?: string;
      payment_session_id?: string;
    };
    const cartId = body.cart_id?.trim() ?? "";
    const paymentSessionId = body.payment_session_id?.trim() ?? "";
    if (!cartId || !paymentSessionId) {
      return jsonResponse(
        { error: "cart_id and payment_session_id are required." },
        400,
      );
    }
    const { user } = await authenticatedUser(request);
    const admin = serviceClient();
    const { data: cart, error: cartError } = await admin.from("entry_carts")
      .select("id,show_id,user_id,status,payment_status,completed_payment_session_id")
      .eq("id", cartId).maybeSingle();
    if (cartError || !cart || cart.user_id !== user.id) {
      throw new Error("You do not have access to this payment attempt.");
    }
    const { data: attempt, error: attemptError } = await admin
      .from("show_payment_sessions")
      .select("id,cart_id,provider,attempt_status,failure_message,provider_payment_id,metadata")
      .eq("id", paymentSessionId)
      .eq("cart_id", cartId)
      .eq("provider", "square")
      .maybeSingle();
    if (attemptError || !attempt) {
      throw new Error("Square payment attempt not found.");
    }
    const { data: show } = await admin.from("shows").select("name")
      .eq("id", cart.show_id).maybeSingle();

    const metadata = attempt.metadata && typeof attempt.metadata === "object"
      ? attempt.metadata as Record<string, unknown>
      : {};
    const status = String(attempt.attempt_status);
    return jsonResponse({
      payment_session_id: attempt.id,
      show_id: cart.show_id,
      show_name: String(show?.name ?? "Show"),
      status,
      finalized: status === "finalized" &&
        cart.completed_payment_session_id === attempt.id,
      pending: ["created", "pending", "processing"].includes(status),
      terminal: ["failed", "cancelled", "expired", "superseded"].includes(
        status,
      ),
      failure_message: status === "failed" || status === "cancelled"
        ? String(attempt.failure_message ?? "")
        : null,
      application_fee_sent_to_provider:
        metadata.application_fee_sent_to_provider === true,
      application_fee_test_limitation:
        metadata.application_fee_test_limitation ?? null,
    });
  } catch (error) {
    return jsonResponse(
      { error: errorMessage(error) },
      errorMessage(error) === "Authentication required." ? 401 : 400,
    );
  }
});
