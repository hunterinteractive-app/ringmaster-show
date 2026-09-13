import { assertEquals } from "jsr:@std/assert@1";
import type Stripe from "npm:stripe@14.25.0";
import { stripeEventPayload } from "./stripe_event_payload.ts";
Deno.test("durable payload keeps reconciliation fields and omits customer details", () => {
  const event = {livemode:false, account:"acct_test", data:{object:{id:"cs_test", amount_total:500,
    currency:"usd", payment_status:"paid", payment_intent:{id:"pi_test"}, customer_details:{email:"private@example.invalid"},
    metadata:{cart_id:"cart",payment_session_id:"attempt",provider:"stripe",quote_hash:"hash",private_note:"omit"}}}} as unknown as Stripe.Event;
  assertEquals(stripeEventPayload(event), {object_id:"cs_test",account:"acct_test",livemode:false,
    payment_session_id:"attempt",cart_id:"cart",provider:"stripe",quote_hash:"hash",payment_intent:"pi_test",
    amount_total:500,currency:"usd",payment_status:"paid"});
});
