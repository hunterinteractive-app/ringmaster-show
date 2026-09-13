import type Stripe from "npm:stripe@14.25.0";

/** Persist only fields consumed by payment reconciliation, excluding customer
 * addresses, payment details, arbitrary metadata and the signature secret. */
export function stripeEventPayload(event: Stripe.Event): Record<string, unknown> {
  const obj = event.data.object as Stripe.Checkout.Session | Stripe.PaymentIntent;
  const metadata = obj.metadata ?? {};
  const intent = "payment_intent" in obj ? obj.payment_intent : obj.id;
  return {
    object_id: obj.id ?? null,
    account: typeof event.account === "string" ? event.account : null,
    livemode: event.livemode,
    payment_session_id: metadata.payment_session_id ?? null,
    cart_id: metadata.cart_id ?? null,
    provider: metadata.provider ?? null,
    quote_hash: metadata.quote_hash ?? null,
    payment_intent: typeof intent === "string" ? intent : intent?.id ?? null,
    amount_total: "amount_total" in obj ? obj.amount_total : null,
    currency: obj.currency ?? null,
    payment_status: "payment_status" in obj ? obj.payment_status : null,
  };
}
