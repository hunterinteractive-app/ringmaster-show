import {
  finalizePaidCart,
  markPaymentAttemptTerminal,
  recordPaymentEvent,
  setPaymentEventStatus,
  setProviderPaymentState,
} from "../_shared/payment.ts";
import { serviceClient } from "../_shared/supabase.ts";

const backend = serviceClient();

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const rawBody = await request.text();
  const signature = request.headers.get("x-square-hmacsha256-signature") ?? "";
  if (!await validSignature(rawBody, signature)) {
    return new Response("Invalid webhook signature", { status: 400 });
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody) as Record<string, unknown>;
  } catch (_) {
    return new Response("Invalid webhook payload", { status: 400 });
  }
  const eventId = String(event.event_id ?? "").trim();
  const eventType = String(event.type ?? "").trim();
  if (!eventId || !eventType) return new Response("Invalid webhook event", { status: 400 });
  const payment = extractPayment(event);
  const providerPaymentId = String(payment?.id ?? "").trim() || null;
  const referenceId = String(payment?.reference_id ?? "").trim() || null;

  let attempt: SavedAttempt | null = null;
  let claimed = false;
  try {
    attempt = await findAttempt(providerPaymentId, referenceId);
    const recorded = await recordPaymentEvent(backend, {
      provider: "square",
      eventId,
      eventType,
      payload: event,
      paymentSessionId: attempt?.id ?? (isUuid(referenceId) ? referenceId : null),
      providerPaymentId,
    });
    claimed = recorded.claimed;
    if (!claimed) return response({ duplicate: true });
    if (eventType !== "payment.updated" || !payment || !attempt || !providerPaymentId) {
      await setPaymentEventStatus(backend, { provider: "square", eventId,
        status: "ignored", paymentSessionId: attempt?.id ?? null, providerPaymentId });
      return response({ ignored: true });
    }
    await setPaymentEventStatus(backend, { provider: "square", eventId,
      status: "processing", paymentSessionId: attempt.id, providerPaymentId });
    validatePayment(payment, attempt);
    await validateMerchantAndLocation(payment, attempt);
    const status = String(payment.status ?? "").toUpperCase();
    if (status === "COMPLETED") {
      await setProviderPaymentState(backend, { paymentSessionId: attempt.id,
        provider: "square", providerPaymentId, providerStatus: "COMPLETED" });
      await finalizePaidCart(backend, { cartId: attempt.cart_id,
        paymentSessionId: attempt.id, provider: "square", providerPaymentId,
        amountCents: attempt.expected_amount_cents, currency: attempt.expected_currency });
    } else if (status === "PENDING" || status === "APPROVED") {
      await setProviderPaymentState(backend, { paymentSessionId: attempt.id,
        provider: "square", providerPaymentId,
        providerStatus: status as "PENDING" | "APPROVED" });
    } else if (status === "FAILED" || status === "CANCELED") {
      await markPaymentAttemptTerminal(backend, { paymentSessionId: attempt.id,
        provider: "square", status: status === "FAILED" ? "failed" : "cancelled",
        failureCode: `square_${status.toLowerCase()}`,
        failureMessage: `Square payment ${status.toLowerCase()}.`, providerPaymentId });
    } else {
      await setPaymentEventStatus(backend, { provider: "square", eventId,
        status: "ignored", paymentSessionId: attempt.id, providerPaymentId });
      return response({ ignored: true });
    }
    await setPaymentEventStatus(backend, { provider: "square", eventId,
      status: "processed", paymentSessionId: attempt.id, providerPaymentId });
    return response({ processed: true });
  } catch (error) {
    if (claimed) {
      try {
        await setPaymentEventStatus(backend, { provider: "square", eventId,
          status: "failed", error: safeError(error),
          paymentSessionId: attempt?.id ?? null, providerPaymentId });
      } catch (_) { /* Keep the original failure. */ }
    }
    console.error("Square webhook processing failed", {
      eventId, eventType, error: safeError(error),
    });
    return new Response("Webhook processing failed", { status: 500 });
  }
});

type SavedAttempt = { id: string; show_id: string; cart_id: string; provider: string;
  provider_payment_id: string | null; expected_amount_cents: number;
  expected_currency: string; platform_fee_cents: number; attempt_status: string };

async function findAttempt(paymentId: string | null, referenceId: string | null): Promise<SavedAttempt | null> {
  if (paymentId) {
    const { data, error } = await backend.from("show_payment_sessions")
      .select("id,show_id,cart_id,provider,provider_payment_id,expected_amount_cents,expected_currency,platform_fee_cents,attempt_status")
      .eq("provider", "square").eq("provider_payment_id", paymentId).maybeSingle();
    if (error) throw new Error("Unable to locate Square payment attempt.");
    if (data) return data as SavedAttempt;
  }
  if (!isUuid(referenceId)) return null;
  const { data, error } = await backend.from("show_payment_sessions")
    .select("id,show_id,cart_id,provider,provider_payment_id,expected_amount_cents,expected_currency,platform_fee_cents,attempt_status")
    .eq("provider", "square").eq("id", referenceId).maybeSingle();
  if (error) throw new Error("Unable to locate Square payment attempt.");
  if (data?.provider_payment_id && paymentId && data.provider_payment_id !== paymentId) {
    throw new Error("Square payment ID does not match the referenced attempt.");
  }
  return data as SavedAttempt | null;
}

function validatePayment(payment: Record<string, unknown>, attempt: SavedAttempt): void {
  if (attempt.provider !== "square") throw new Error("Provider mismatch.");
  const amount = payment.amount_money as Record<string, unknown> | undefined;
  if (!amount || Number(amount.amount) !== attempt.expected_amount_cents) {
    throw new Error("Square amount does not match the saved quote.");
  }
  if (String(amount.currency ?? "").toLowerCase() !== attempt.expected_currency.toLowerCase()) {
    throw new Error("Square currency does not match the saved quote.");
  }
  if (payment.reference_id && String(payment.reference_id) !== attempt.id) {
    throw new Error("Square reference does not match the payment attempt.");
  }
  if (payment.app_fee_money) {
    const appFee = payment.app_fee_money as Record<string, unknown>;
    if (Number(appFee.amount) !== attempt.platform_fee_cents ||
        String(appFee.currency ?? "").toLowerCase() !== attempt.expected_currency.toLowerCase()) {
      throw new Error("Square application fee does not match the saved quote.");
    }
  }
}

async function validateMerchantAndLocation(payment: Record<string, unknown>, attempt: SavedAttempt): Promise<void> {
  const { data, error } = await backend.from("show_payment_account_links")
    .select("provider_account_id,provider_location_id")
    .eq("show_id", attempt.show_id).eq("provider", "square").maybeSingle();
  if (error || !data) throw new Error("Square account link is missing.");
  if (String(payment.location_id ?? "") !== String(data.provider_location_id ?? "") ||
      (payment.merchant_id && String(payment.merchant_id) !== String(data.provider_account_id ?? ""))) {
    throw new Error("Square merchant or location mismatch.");
  }
}

function extractPayment(event: Record<string, unknown>): Record<string, unknown> | null {
  const data = event.data as Record<string, unknown> | undefined;
  const object = data?.object as Record<string, unknown> | undefined;
  const payment = object?.payment;
  return payment && typeof payment === "object" && !Array.isArray(payment)
    ? payment as Record<string, unknown> : null;
}

async function validSignature(body: string, signature: string): Promise<boolean> {
  if (!signature) return false;
  const key = Deno.env.get("SQUARE_WEBHOOK_SIGNATURE_KEY")?.trim() ?? "";
  const url = Deno.env.get("SQUARE_WEBHOOK_URL")?.trim() ?? "";
  if (!key || !url) return false;
  let supplied: Uint8Array;
  try { supplied = Uint8Array.from(atob(signature), (c) => c.charCodeAt(0)); }
  catch (_) { return false; }
  const cryptoKey = await crypto.subtle.importKey("raw", new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  return crypto.subtle.verify("HMAC", cryptoKey, supplied.buffer as ArrayBuffer,
    new TextEncoder().encode(url + body));
}

function response(body: unknown): Response {
  return new Response(JSON.stringify(body), { status: 200,
    headers: { "Content-Type": "application/json" } });
}
function safeError(error: unknown): string {
  return error instanceof Error ? error.message.slice(0, 500) : "Unexpected processing error";
}
function isUuid(value: string | null): value is string {
  return value != null && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
