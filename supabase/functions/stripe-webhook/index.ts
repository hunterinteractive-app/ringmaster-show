import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "npm:stripe@14.25.0";
import { serviceClient } from "../_shared/supabase.ts";
import { stripeEventPayload } from "../_shared/stripe_event_payload.ts";
import { queuedPaymentEventResponse } from "../_shared/payment_event_response.ts";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}.`);
  return value;
}
const stripe = new Stripe(requiredEnv("STRIPE_SECRET_KEY"), {
  apiVersion: "2024-04-10" as Stripe.LatestApiVersion,
});
const secret = requiredEnv("STRIPE_WEBHOOK_SECRET");
const backend = serviceClient();

serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const signature = request.headers.get("stripe-signature");
  if (!signature) return new Response("Missing signature", { status: 400 });
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(await request.text(), signature, secret);
  } catch {
    return new Response("Invalid webhook signature", { status: 400 });
  }
  try {
    const { data, error } = await backend.rpc("enqueue_stripe_payment_event", {
      p_event_id: event.id, p_event_type: event.type, p_payload: stripeEventPayload(event),
    });
    // A timeout after commit is safe: the next delivery uses the same event ID.
    if (error || !data) throw new Error("Payment event could not be durably saved");
    return queuedPaymentEventResponse(data);
  } catch {
    console.error("Stripe event enqueue failed", { eventId: event.id, eventType: event.type });
    return new Response("Payment event could not be saved; retry delivery", {
      status: 503, headers: { "Retry-After": "2" },
    });
  }
});
