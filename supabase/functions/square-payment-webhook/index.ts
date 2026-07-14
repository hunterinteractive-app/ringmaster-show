import {
  recordPaymentEvent,
  setPaymentEventStatus,
} from "../_shared/payment.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { squareGet } from "../_shared/square.ts";
import { loadSquareAuthorization } from "../_shared/square_credentials.ts";
import {
  findSquarePaymentAttempt,
  reconcileSquarePayment,
  retrieveSquarePaymentForAttempt,
} from "../_shared/square_payment_reconciler.ts";
import type {
  SquarePaymentAttempt,
} from "../_shared/square_payment_reconciler.ts";

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
  let attempt: SquarePaymentAttempt | null = null;
  let claimed = false;

  try {
    attempt = await findSquarePaymentAttempt(backend, {
      providerPaymentId,
      providerOrderId: orderId,
      paymentSessionId: isUuid(referenceId) ? referenceId : null,
    });
    if (!attempt && providerPaymentId && eventMerchantId) {
      const recovered = await recoverPayment(
        providerPaymentId,
        eventMerchantId,
      );
      if (recovered) {
        payment = recovered;
        orderId = text(recovered.order_id);
        attempt = await findSquarePaymentAttempt(backend, {
          providerPaymentId,
          providerOrderId: orderId,
        });
      }
    }
    if (eventType === "order.updated" && attempt && !payment) {
      const lookup = await retrieveSquarePaymentForAttempt(backend, attempt);
      payment = lookup?.payment ?? null;
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
    const result = await reconcileSquarePayment(backend, {
      attempt,
      payment,
    });
    if (!result.processed) {
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
  attempt: SquarePaymentAttempt | null,
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
