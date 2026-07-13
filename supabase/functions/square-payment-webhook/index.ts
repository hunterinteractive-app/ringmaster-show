import {
  finalizePaidCart,
  markPaymentAttemptTerminal,
  recordPaymentEvent,
  setPaymentEventStatus,
  setProviderPaymentState,
} from "../_shared/payment.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { squareGet } from "../_shared/square.ts";
import { loadSquareAuthorization } from "../_shared/square_credentials.ts";

const backend = serviceClient();

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
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
  if (!eventId || !eventType) {
    return new Response("Invalid webhook event", { status: 400 });
  }

  let payment = extractPayment(event);
  let providerPaymentId = text(payment?.id);
  let orderId = text(payment?.order_id) ?? extractOrderId(event);
  const referenceId = text(payment?.reference_id);
  const eventMerchantId = text(event.merchant_id);
  let attempt: SavedAttempt | null = null;
  let claimed = false;

  try {
    attempt = await findAttempt(providerPaymentId, orderId, referenceId);
    if (!attempt && providerPaymentId && eventMerchantId) {
      const recovered = await recoverPayment(
        providerPaymentId,
        eventMerchantId,
      );
      if (recovered) {
        payment = recovered;
        orderId = text(recovered.order_id);
        attempt = await findAttempt(providerPaymentId, orderId, null);
      }
    }
    if (eventType === "order.updated" && attempt && !payment) {
      payment = await paymentForOrder(attempt, orderId);
      providerPaymentId = text(payment?.id);
    }

    const recorded = await recordPaymentEvent(backend, {
      provider: "square",
      eventId,
      eventType,
      payload: event,
      paymentSessionId: attempt?.id ??
        (isUuid(referenceId) ? referenceId : null),
      providerPaymentId,
    });
    claimed = recorded.claimed;
    if (!claimed) return response({ duplicate: true });

    if (
      !["payment.updated", "order.updated"].includes(eventType) ||
      !payment || !attempt || !providerPaymentId
    ) {
      await updateEvent(eventId, "ignored", attempt, providerPaymentId);
      return response({ ignored: true });
    }
    if (
      ["failed", "cancelled", "expired", "superseded"].includes(
        attempt.attempt_status,
      )
    ) {
      await updateEvent(eventId, "ignored", attempt, providerPaymentId);
      return response({ ignored: true, terminal_attempt: true });
    }

    await updateEvent(eventId, "processing", attempt, providerPaymentId);
    validatePayment(payment, attempt);
    await validateMerchantAndLocation(payment, attempt);
    const status = String(payment.status ?? "").toUpperCase();
    if (status === "COMPLETED") {
      await setProviderPaymentState(backend, {
        paymentSessionId: attempt.id,
        provider: "square",
        providerPaymentId,
        providerStatus: "COMPLETED",
      });
      await finalizePaidCart(backend, {
        cartId: attempt.cart_id,
        paymentSessionId: attempt.id,
        provider: "square",
        providerPaymentId,
        amountCents: attempt.expected_amount_cents,
        currency: attempt.expected_currency,
      });
    } else if (status === "PENDING" || status === "APPROVED") {
      await setProviderPaymentState(backend, {
        paymentSessionId: attempt.id,
        provider: "square",
        providerPaymentId,
        providerStatus: status as "PENDING" | "APPROVED",
      });
    } else if (status === "FAILED" || status === "CANCELED") {
      await markPaymentAttemptTerminal(backend, {
        paymentSessionId: attempt.id,
        provider: "square",
        status: status === "FAILED" ? "failed" : "cancelled",
        failureCode: `square_${status.toLowerCase()}`,
        failureMessage: `Square payment ${status.toLowerCase()}.`,
        providerPaymentId,
      });
    } else {
      await updateEvent(eventId, "ignored", attempt, providerPaymentId);
      return response({ ignored: true });
    }
    await updateEvent(eventId, "processed", attempt, providerPaymentId);
    return response({ processed: true });
  } catch (error) {
    if (claimed) {
      try {
        await setPaymentEventStatus(backend, {
          provider: "square",
          eventId,
          status: "failed",
          error: safeError(error),
          paymentSessionId: attempt?.id ?? null,
          providerPaymentId,
        });
      } catch (_) {
        // Keep the original processing failure.
      }
    }
    console.error("Square webhook processing failed", {
      eventId,
      eventType,
      error: safeError(error),
    });
    return new Response("Webhook processing failed", { status: 500 });
  }
});

type SavedAttempt = {
  id: string;
  show_id: string;
  cart_id: string;
  provider: string;
  provider_order_id: string | null;
  provider_payment_id: string | null;
  expected_amount_cents: number;
  expected_currency: string;
  platform_fee_cents: number;
  attempt_status: string;
  metadata: Record<string, unknown> | null;
};

const attemptColumns =
  "id,show_id,cart_id,provider,provider_order_id,provider_payment_id," +
  "expected_amount_cents,expected_currency,platform_fee_cents,attempt_status,metadata";

async function findAttempt(
  paymentId: string | null,
  orderId: string | null,
  referenceId: string | null,
): Promise<SavedAttempt | null> {
  if (paymentId) {
    const result = await backend.from("show_payment_sessions")
      .select(attemptColumns).eq("provider", "square")
      .eq("provider_payment_id", paymentId).maybeSingle();
    if (result.error) {
      throw new Error("Unable to locate Square payment attempt.");
    }
    if (result.data) return result.data as unknown as SavedAttempt;
  }
  if (orderId) {
    const result = await backend.from("show_payment_sessions")
      .select(attemptColumns).eq("provider", "square")
      .eq("provider_order_id", orderId).maybeSingle();
    if (result.error) throw new Error("Unable to locate Square order attempt.");
    if (result.data) return result.data as unknown as SavedAttempt;
  }
  if (!isUuid(referenceId)) return null;
  const result = await backend.from("show_payment_sessions")
    .select(attemptColumns).eq("provider", "square")
    .eq("id", referenceId).maybeSingle();
  if (result.error) throw new Error("Unable to locate Square payment attempt.");
  return result.data as unknown as SavedAttempt | null;
}

async function recoverPayment(
  paymentId: string,
  merchantId: string,
): Promise<Record<string, unknown> | null> {
  const { data: link, error } = await backend.from("show_payment_account_links")
    .select("show_id").eq("provider", "square")
    .eq("provider_account_id", merchantId).maybeSingle();
  if (error || !link) return null;
  const authorization = await loadSquareAuthorization(
    backend,
    String(link.show_id),
    { requireReady: false },
  );
  const result = await squareGet(
    `/v2/payments/${encodeURIComponent(paymentId)}`,
    authorization.accessToken,
  );
  return objectOrNull(result.payment);
}

async function paymentForOrder(
  attempt: SavedAttempt,
  orderId: string | null,
): Promise<Record<string, unknown> | null> {
  const exactOrderId = orderId ?? attempt.provider_order_id;
  if (!exactOrderId || exactOrderId !== attempt.provider_order_id) return null;
  const authorization = await loadSquareAuthorization(
    backend,
    attempt.show_id,
    { requireReady: false },
  );
  const result = await squareGet(
    `/v2/orders/${encodeURIComponent(exactOrderId)}`,
    authorization.accessToken,
  );
  const order = objectOrNull(result.order);
  const tenders = Array.isArray(order?.tenders) ? order.tenders : [];
  const paymentId = tenders.map((tender) => objectOrNull(tender))
    .map((tender) => text(tender?.payment_id)).find(Boolean);
  if (!paymentId) return null;
  const paymentResult = await squareGet(
    `/v2/payments/${encodeURIComponent(paymentId)}`,
    authorization.accessToken,
  );
  return objectOrNull(paymentResult.payment);
}

function validatePayment(
  payment: Record<string, unknown>,
  attempt: SavedAttempt,
): void {
  if (attempt.provider !== "square") throw new Error("Provider mismatch.");
  if (
    !attempt.provider_order_id ||
    text(payment.order_id) !== attempt.provider_order_id
  ) {
    throw new Error("Square order does not match the saved payment attempt.");
  }
  const amount = objectOrNull(payment.amount_money);
  if (!amount || Number(amount.amount) !== attempt.expected_amount_cents) {
    throw new Error("Square amount does not match the saved quote.");
  }
  if (
    String(amount.currency ?? "").toLowerCase() !==
      attempt.expected_currency.toLowerCase()
  ) {
    throw new Error("Square currency does not match the saved quote.");
  }
  const metadata = attempt.metadata ?? {};
  if (metadata.application_fee_sent_to_provider === true) {
    const appFee = objectOrNull(payment.app_fee_money);
    if (
      !appFee || Number(appFee.amount) !== attempt.platform_fee_cents ||
      String(appFee.currency ?? "").toLowerCase() !==
        attempt.expected_currency.toLowerCase()
    ) {
      throw new Error("Square application fee does not match the saved quote.");
    }
  }
}

async function validateMerchantAndLocation(
  payment: Record<string, unknown>,
  attempt: SavedAttempt,
): Promise<void> {
  const { data, error } = await backend.from("show_payment_account_links")
    .select("provider_account_id,provider_location_id")
    .eq("show_id", attempt.show_id).eq("provider", "square").maybeSingle();
  if (error || !data) throw new Error("Square account link is missing.");
  if (
    String(payment.location_id ?? "") !==
      String(data.provider_location_id ?? "") ||
    (payment.merchant_id && String(payment.merchant_id) !==
        String(data.provider_account_id ?? ""))
  ) {
    throw new Error("Square merchant or location mismatch.");
  }
}

function extractPayment(event: Record<string, unknown>) {
  const data = objectOrNull(event.data);
  const object = objectOrNull(data?.object);
  return objectOrNull(object?.payment);
}
function extractOrderId(event: Record<string, unknown>): string | null {
  const data = objectOrNull(event.data);
  const object = objectOrNull(data?.object);
  const updated = objectOrNull(object?.order_updated);
  return text(updated?.order_id) ?? text(data?.id);
}
function objectOrNull(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}
function text(value: unknown): string | null {
  const result = String(value ?? "").trim();
  return result ? result : null;
}

async function updateEvent(
  eventId: string,
  status: "processing" | "processed" | "ignored",
  attempt: SavedAttempt | null,
  providerPaymentId: string | null,
) {
  await setPaymentEventStatus(backend, {
    provider: "square",
    eventId,
    status,
    paymentSessionId: attempt?.id ?? null,
    providerPaymentId,
  });
}

async function validSignature(
  body: string,
  signature: string,
): Promise<boolean> {
  if (!signature) return false;
  const key = Deno.env.get("SQUARE_WEBHOOK_SIGNATURE_KEY")?.trim() ?? "";
  const url = Deno.env.get("SQUARE_WEBHOOK_URL")?.trim() ?? "";
  if (!key || !url) return false;
  let supplied: Uint8Array;
  try {
    supplied = Uint8Array.from(
      atob(signature),
      (character) => character.charCodeAt(0),
    );
  } catch (_) {
    return false;
  }
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  return crypto.subtle.verify(
    "HMAC",
    cryptoKey,
    supplied.buffer as ArrayBuffer,
    new TextEncoder().encode(url + body),
  );
}

function response(body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
function safeError(error: unknown): string {
  return error instanceof Error
    ? error.message.slice(0, 500)
    : "Unexpected processing error";
}
function isUuid(value: string | null): value is string {
  return value != null &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}
