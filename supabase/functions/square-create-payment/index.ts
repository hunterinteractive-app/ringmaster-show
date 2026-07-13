import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  attachProviderSession,
  claimPaymentAttemptClientKey,
  createPaymentQuoteAttempt,
  finalizePaidCart,
  markPaymentAttemptTerminal,
  PaymentAttempt,
  setProviderPaymentState,
} from "../_shared/payment.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { sha256 } from "../_shared/token_crypto.ts";
import { SquareRequestError, squareRequest } from "../_shared/square.ts";
import { loadSquareAuthorization } from "../_shared/square_credentials.ts";

type RequestBody = { cart_id?: string; source_id?: string; client_attempt_key?: string };

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const backend = serviceClient();
  let attempt: PaymentAttempt | null = null;
  try {
    const { user } = await authenticatedUser(request);
    const body = await request.json() as RequestBody;
    const cartId = body.cart_id?.trim() ?? "";
    const sourceId = body.source_id?.trim() ?? "";
    const clientAttemptKey = body.client_attempt_key?.trim() ?? "";
    if (!cartId || !sourceId || !clientAttemptKey) {
      return jsonResponse({ error: "cart_id, source_id, and client_attempt_key are required." }, 400);
    }
    if (sourceId.length > 2048 || clientAttemptKey.length > 200) {
      return jsonResponse({ error: "Invalid payment request." }, 400);
    }

    const { data: cart, error: cartError } = await backend.from("entry_carts")
      .select("show_id,user_id").eq("id", cartId).maybeSingle();
    if (cartError || !cart || cart.user_id !== user.id) {
      throw new Error("You do not have access to this cart.");
    }
    const authorization = await loadSquareAuthorization(
      backend,
      String(cart.show_id),
    );

    attempt = await createPaymentQuoteAttempt(backend, {
      cartId,
      userId: user.id,
      provider: "square",
      platformFeeDefaultPercent: readNumberEnv(
        "RINGMASTER_PLATFORM_FEE_PERCENT",
        0.02,
      ),
      processingFeePercent: readRequiredNumber("SQUARE_PROCESSING_FEE_PERCENT"),
      processingFeeFixedCents: readRequiredInt("SQUARE_PROCESSING_FEE_FIXED_CENTS"),
    });
    const claim = await claimPaymentAttemptClientKey(backend, {
      paymentSessionId: attempt.payment_session_id,
      provider: "square",
      clientAttemptKeyHash: await sha256(clientAttemptKey),
    });
    if (claim.already_finalized === true) {
      return jsonResponse({
        ok: true,
        finalized: true,
        payment_session_id: attempt.payment_session_id,
        provider_payment_id: claim.provider_payment_id,
      });
    }

    const quote = attempt.quote;
    if (quote.show_id !== String(cart.show_id)) {
      throw new Error("Payment quote does not match this cart.");
    }
    if (authorization.currency !== quote.currency.toLowerCase()) {
      throw new Error("The saved checkout currency does not match the Square location.");
    }

    const squareData = await squareRequest("/v2/payments", authorization.accessToken, {
      method: "POST",
      body: JSON.stringify({
        source_id: sourceId,
        idempotency_key: await sha256(`square:${attempt.payment_session_id}`),
        amount_money: {
          amount: quote.expected_amount_cents,
          currency: quote.currency.toUpperCase(),
        },
        app_fee_money: {
          amount: quote.platform_fee_cents,
          currency: quote.currency.toUpperCase(),
        },
        location_id: authorization.locationId,
        autocomplete: true,
        reference_id: attempt.payment_session_id,
        note: `RingMaster Show payment ${attempt.payment_session_id}`,
      }),
    });
    const payment = requireObject(squareData.payment, "Square payment");
    const paymentId = requiredString(payment.id, "Square payment ID");
    const status = requiredString(payment.status, "Square payment status").toUpperCase();
    assertSquarePayment(payment, attempt, authorization);

    if (!attempt.provider_session_id) {
      await attachProviderSession(backend, {
        paymentSessionId: attempt.payment_session_id,
        provider: "square",
        providerSessionId: paymentId,
        checkoutUrl: "",
      });
    } else if (attempt.provider_session_id !== paymentId) {
      throw new Error("Square payment does not match the saved attempt.");
    }

    if (["PENDING", "APPROVED", "COMPLETED"].includes(status)) {
      await setProviderPaymentState(backend, {
        paymentSessionId: attempt.payment_session_id,
        provider: "square",
        providerPaymentId: paymentId,
        providerStatus: status as "PENDING" | "APPROVED" | "COMPLETED",
      });
    }
    if (status === "COMPLETED") {
      await finalizePaidCart(backend, {
        cartId,
        paymentSessionId: attempt.payment_session_id,
        provider: "square",
        providerPaymentId: paymentId,
        amountCents: quote.expected_amount_cents,
        currency: quote.currency,
      });
      return jsonResponse({ ok: true, finalized: true,
        payment_session_id: attempt.payment_session_id, provider_payment_id: paymentId });
    }
    if (status === "PENDING" || status === "APPROVED") {
      return jsonResponse({ ok: true, finalized: false, pending: true,
        payment_session_id: attempt.payment_session_id, provider_payment_id: paymentId });
    }

    await markPaymentAttemptTerminal(backend, {
      paymentSessionId: attempt.payment_session_id,
      provider: "square",
      status: "failed",
      failureCode: `square_${status.toLowerCase()}`,
      failureMessage: "Square declined the payment.",
      providerPaymentId: paymentId,
    });
    return jsonResponse({ error: "The card was declined. Check the card details and try again." }, 402);
  } catch (error) {
    if (attempt && error instanceof SquareRequestError) {
      try {
        await markPaymentAttemptTerminal(backend, {
          paymentSessionId: attempt.payment_session_id,
          provider: "square",
          status: "failed",
          failureCode: error.code,
          failureMessage: error.message,
        });
      } catch (_) { /* Preserve the original provider error. */ }
    }
    const message = error instanceof SquareRequestError
      ? "Square could not complete the payment. Check the card details and try again."
      : errorMessage(error);
    return jsonResponse({ error: message },
      errorMessage(error) === "Authentication required." ? 401 : 400);
  }
});

function assertSquarePayment(
  payment: Record<string, unknown>,
  attempt: PaymentAttempt,
  authorization: { merchantId: string; locationId: string },
): void {
  const money = requireObject(payment.amount_money, "Square amount");
  if (Number(money.amount) !== attempt.quote.expected_amount_cents) {
    throw new Error("Square amount does not match the saved quote.");
  }
  if (String(money.currency ?? "").toLowerCase() !== attempt.quote.currency.toLowerCase()) {
    throw new Error("Square currency does not match the saved quote.");
  }
  if (String(payment.location_id ?? "") !== authorization.locationId ||
      (payment.merchant_id && String(payment.merchant_id) !== authorization.merchantId)) {
    throw new Error("Square merchant or location does not match this show.");
  }
  if (String(payment.reference_id ?? "") !== attempt.payment_session_id) {
    throw new Error("Square payment reference does not match the saved attempt.");
  }
  if (payment.app_fee_money) {
    const appFee = requireObject(payment.app_fee_money, "Square application fee");
    if (Number(appFee.amount) !== attempt.quote.platform_fee_cents ||
        String(appFee.currency ?? "").toLowerCase() !== attempt.quote.currency.toLowerCase()) {
      throw new Error("Square application fee does not match the saved quote.");
    }
  }
}

function requireObject(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label} is missing.`);
  return value as Record<string, unknown>;
}
function requiredString(value: unknown, label: string): string {
  const text = String(value ?? "").trim();
  if (!text) throw new Error(`${label} is missing.`);
  return text;
}
function readRequiredNumber(name: string): number {
  const value = Number(Deno.env.get(name));
  if (!Number.isFinite(value) || value < 0) throw new Error(`Missing or invalid server configuration: ${name}.`);
  return value;
}
function readNumberEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}
function readRequiredInt(name: string): number {
  return Math.round(readRequiredNumber(name));
}
