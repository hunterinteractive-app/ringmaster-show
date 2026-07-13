import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "npm:stripe@14.25.0";
import {
  finalizePaidCart,
  markPaymentAttemptTerminal,
  recordPaymentEvent,
  setPaymentEventStatus,
} from "../_shared/payment.ts";
import { serviceClient } from "../_shared/supabase.ts";

const stripe = new Stripe(requiredEnv("STRIPE_SECRET_KEY"), {
  // Preserve the deployed API version; Stripe 14's bundled type narrows this
  // field to its release-time default even though the runtime accepts it.
  apiVersion: "2024-04-10" as Stripe.LatestApiVersion,
});
const webhookSecret = requiredEnv("STRIPE_WEBHOOK_SECRET");
const backend = serviceClient();

type SavedAttempt = {
  id: string;
  cart_id: string;
  provider: string;
  provider_session_id: string | null;
  provider_payment_id: string | null;
  quote_hash: string;
  expected_amount_cents: number;
  expected_currency: string;
  attempt_status: string;
  metadata: Record<string, unknown>;
};

serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const signature = request.headers.get("stripe-signature");
  if (!signature) return new Response("Missing signature", { status: 400 });

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      await request.text(),
      signature,
      webhookSecret,
    );
  } catch {
    return new Response("Invalid webhook signature", { status: 400 });
  }

  const identity = eventIdentity(event);
  let claimed = false;
  try {
    const recorded = await recordPaymentEvent(backend, {
      provider: "stripe",
      eventId: event.id,
      eventType: event.type,
      paymentSessionId: identity.paymentSessionId,
      providerPaymentId: identity.providerPaymentId,
      payload: {
        stripe_object_id: identity.objectId,
        stripe_account_id: typeof event.account === "string"
          ? event.account
          : null,
        livemode: event.livemode,
      },
    });
    claimed = recorded.claimed;
    if (!claimed) return successResponse({ duplicate: true });

    switch (event.type) {
      case "checkout.session.completed":
        await handleCompleted(
          event.id,
          event.data.object as Stripe.Checkout.Session,
        );
        break;
      case "checkout.session.expired":
        await handleExpired(
          event.id,
          event.data.object as Stripe.Checkout.Session,
        );
        break;
      case "payment_intent.payment_failed":
        await handleFailed(
          event.id,
          event.data.object as Stripe.PaymentIntent,
        );
        break;
      default:
        await setPaymentEventStatus(backend, {
          provider: "stripe",
          eventId: event.id,
          status: "ignored",
          paymentSessionId: identity.paymentSessionId,
          providerPaymentId: identity.providerPaymentId,
        });
        return successResponse({ ignored: true });
    }

    await setPaymentEventStatus(backend, {
      provider: "stripe",
      eventId: event.id,
      status: "processed",
      paymentSessionId: identity.paymentSessionId,
      providerPaymentId: identity.providerPaymentId,
    });
    return successResponse({ processed: true });
  } catch (error) {
    if (claimed) {
      try {
        await setPaymentEventStatus(backend, {
          provider: "stripe",
          eventId: event.id,
          status: "failed",
          error: safeError(error),
          paymentSessionId: identity.paymentSessionId,
          providerPaymentId: identity.providerPaymentId,
        });
      } catch {
        // Preserve the original failure; no token or payload values are logged.
      }
    }
    console.error("Stripe webhook processing failed", {
      eventId: event.id,
      eventType: event.type,
      error: safeError(error),
    });
    return new Response("Webhook processing failed", { status: 500 });
  }
});

async function handleCompleted(
  eventId: string,
  session: Stripe.Checkout.Session,
): Promise<void> {
  const metadata = session.metadata ?? {};
  const attempt = metadata.payment_session_id
    ? await loadAttempt(metadata.payment_session_id)
    : await loadAttemptByProviderSession(session.id);
  const paymentSessionId = attempt.id;
  const cartId = metadata.cart_id?.trim() || attempt.cart_id;
  const quoteHash = metadata.quote_hash?.trim() ?? null;
  if (metadata.provider && metadata.provider !== "stripe") {
    throw new Error("Provider metadata mismatch");
  }
  if (!quoteHash && attempt.metadata?.legacy_backfill !== true) {
    throw new Error("Stripe metadata is missing quote_hash");
  }
  await setPaymentEventStatus(backend, {
    provider: "stripe",
    eventId,
    status: "processing",
    paymentSessionId,
  });
  if (attempt.attempt_status === "finalized") return;
  if (
    ["failed", "cancelled", "expired", "superseded"].includes(
      attempt.attempt_status,
    )
  ) {
    return;
  }
  if (
    attempt.cart_id !== cartId ||
    (quoteHash != null && attempt.quote_hash !== quoteHash)
  ) {
    throw new Error("Checkout metadata does not match the saved attempt");
  }
  if (
    attempt.provider !== "stripe" || attempt.provider_session_id !== session.id
  ) {
    throw new Error("Stripe Checkout Session does not match the saved attempt");
  }
  if (session.payment_status !== "paid") {
    throw new Error("Stripe Checkout Session is not paid");
  }

  const amountCents = session.amount_total;
  const currency = session.currency?.toLowerCase();
  if (amountCents == null || amountCents !== attempt.expected_amount_cents) {
    throw new Error("Stripe amount does not match the saved quote");
  }
  if (!currency || currency !== attempt.expected_currency.toLowerCase()) {
    throw new Error("Stripe currency does not match the saved quote");
  }

  const paymentIntentId = typeof session.payment_intent === "string"
    ? session.payment_intent
    : session.payment_intent?.id;
  if (!paymentIntentId) throw new Error("Stripe payment intent is missing");
  if (
    attempt.provider_payment_id &&
    attempt.provider_payment_id !== paymentIntentId
  ) {
    throw new Error("Stripe payment intent does not match the saved attempt");
  }

  await finalizePaidCart(backend, {
    cartId,
    paymentSessionId,
    provider: "stripe",
    providerPaymentId: paymentIntentId,
    amountCents,
    currency,
  });
}

async function handleExpired(
  eventId: string,
  session: Stripe.Checkout.Session,
): Promise<void> {
  const metadata = session.metadata ?? {};
  const attempt = metadata.payment_session_id
    ? await loadAttempt(metadata.payment_session_id)
    : await loadAttemptByProviderSession(session.id);
  const paymentSessionId = attempt.id;
  await setPaymentEventStatus(backend, {
    provider: "stripe",
    eventId,
    status: "processing",
    paymentSessionId,
  });
  if (attempt.attempt_status === "finalized") return;
  if (
    attempt.provider !== "stripe" || attempt.provider_session_id !== session.id
  ) {
    throw new Error("Expired Stripe session does not match the saved attempt");
  }
  await markPaymentAttemptTerminal(backend, {
    paymentSessionId,
    provider: "stripe",
    status: "expired",
    failureCode: "checkout_session_expired",
    failureMessage: "Stripe Checkout Session expired.",
  });
}

async function handleFailed(
  eventId: string,
  paymentIntent: Stripe.PaymentIntent,
): Promise<void> {
  const metadata = paymentIntent.metadata ?? {};
  const attempt = metadata.payment_session_id
    ? await loadAttempt(metadata.payment_session_id)
    : await loadActiveAttemptForCart(requiredMetadata(metadata, "cart_id"));
  const paymentSessionId = attempt.id;
  await setPaymentEventStatus(backend, {
    provider: "stripe",
    eventId,
    status: "processing",
    paymentSessionId,
    providerPaymentId: paymentIntent.id,
  });
  if (attempt.attempt_status === "finalized") return;
  if (attempt.provider !== "stripe") throw new Error("Provider mismatch");
  if (
    attempt.provider_payment_id &&
    attempt.provider_payment_id !== paymentIntent.id
  ) {
    throw new Error("Failed payment intent does not match the saved attempt");
  }
  await markPaymentAttemptTerminal(backend, {
    paymentSessionId,
    provider: "stripe",
    status: "failed",
    failureCode: paymentIntent.last_payment_error?.code ?? "payment_failed",
    failureMessage: paymentIntent.last_payment_error?.message ??
      "Payment failed.",
    providerPaymentId: paymentIntent.id,
  });
}

async function loadAttempt(id: string): Promise<SavedAttempt> {
  const { data, error } = await backend
    .from("show_payment_sessions")
    .select(
      "id,cart_id,provider,provider_session_id,provider_payment_id,quote_hash,expected_amount_cents,expected_currency,attempt_status,metadata",
    )
    .eq("id", id)
    .maybeSingle();
  if (error || !data) throw new Error("Payment attempt not found");
  return data as SavedAttempt;
}

async function loadAttemptByProviderSession(
  providerSessionId: string,
): Promise<SavedAttempt> {
  const { data, error } = await backend
    .from("show_payment_sessions")
    .select(
      "id,cart_id,provider,provider_session_id,provider_payment_id,quote_hash,expected_amount_cents,expected_currency,attempt_status,metadata",
    )
    .eq("provider", "stripe")
    .eq("provider_session_id", providerSessionId)
    .maybeSingle();
  if (error || !data) throw new Error("Payment attempt not found");
  return data as SavedAttempt;
}

async function loadActiveAttemptForCart(cartId: string): Promise<SavedAttempt> {
  const { data: cart, error } = await backend
    .from("entry_carts")
    .select("active_payment_session_id")
    .eq("id", cartId)
    .maybeSingle();
  const id = cart?.active_payment_session_id?.toString();
  if (error || !id) throw new Error("Active payment attempt not found");
  return await loadAttempt(id);
}

function eventIdentity(event: Stripe.Event): {
  objectId: string | null;
  paymentSessionId: string | null;
  providerPaymentId: string | null;
} {
  const object = event.data.object as
    | Stripe.Checkout.Session
    | Stripe.PaymentIntent;
  const metadata = object.metadata ?? {};
  const paymentIntent = "payment_intent" in object
    ? object.payment_intent
    : object.id;
  return {
    objectId: object.id ?? null,
    paymentSessionId: metadata.payment_session_id ?? null,
    providerPaymentId: typeof paymentIntent === "string"
      ? paymentIntent
      : paymentIntent?.id ?? null,
  };
}

function requiredMetadata(metadata: Stripe.Metadata, key: string): string {
  const value = metadata[key]?.trim();
  if (!value) throw new Error(`Stripe metadata is missing ${key}`);
  return value;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}.`);
  return value;
}

function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : "Unexpected error";
  return message.slice(0, 1000);
}

function successResponse(extra: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ received: true, ...extra }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
