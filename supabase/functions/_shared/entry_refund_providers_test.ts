import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { stripeRefundProvider } from "./entry_refund_providers.ts";
import type { EntryRefund } from "./entry_refund_processor.ts";

const request: EntryRefund = {
  id: "refund-test",
  show_id: "show-test",
  exhibitor_id: "ex-test",
  provider: "stripe",
  provider_payment_id: "pi_test",
  provider_account_id: "acct_original",
  provider_refund_id: null,
  currency: "usd",
  entry_amount_cents: 1000,
  online_fee_cents: 0,
  reason: "Entry canceled",
  status: "prepared",
  attempted_at: new Date().toISOString(),
};
const result = {
  id: "re_test",
  payment_intent: "pi_test",
  amount: 1000,
  currency: "usd",
  status: "succeeded",
};
Deno.test("Stripe direct refund uses original account, durable key and retains online fees", async () => {
  Deno.env.set("STRIPE_SECRET_KEY", "sk_test_fixture");
  const calls: { url: string; init: RequestInit }[] = [];
  const adapter = stripeRefundProvider(async (url, init = {}) => {
    calls.push({ url: String(url), init });
    return Response.json(
      String(url).includes("payment_intents")
        ? { id: "pi_test" }
        : init.method === "POST"
        ? result
        : { data: [], has_more: false },
    );
  });
  assertEquals(await adapter.find(request), null);
  assertEquals((await adapter.create(request)).status, "succeeded");
  const sent = calls.at(-1)!;
  assertEquals(
    new Headers(sent.init.headers).get("Stripe-Account"),
    "acct_original",
  );
  assertEquals(
    new Headers(sent.init.headers).get("Idempotency-Key"),
    "entry-refund:refund-test",
  );
  const body = new URLSearchParams(sent.init.body as URLSearchParams);
  assertEquals(body.get("amount"), "1000");
  assertEquals(body.get("refund_application_fee"), "false");
  assertEquals(body.has("reverse_transfer"), false);
});
Deno.test("Stripe included online fees are added once and application fees may be returned", async () => {
  Deno.env.set("STRIPE_SECRET_KEY", "sk_test_fixture");
  let sent: URLSearchParams | null = null;
  const adapter = stripeRefundProvider(async (_url, init = {}) => {
    if (init.method === "POST") {
      sent = init.body as URLSearchParams;
      return Response.json({ ...result, amount: 1050 });
    }
    return Response.json({ id: "pi_test", data: [], has_more: false });
  });
  await adapter.find(request);
  await adapter.create({ ...request, online_fee_cents: 50 });
  assertEquals(sent!.get("amount"), "1050");
  assertEquals(sent!.get("refund_application_fee"), "true");
});
Deno.test("historical destination charge reverses only the verified original transfer", async () => {
  Deno.env.set("STRIPE_SECRET_KEY", "sk_test_fixture");
  let sent: RequestInit = {};
  const adapter = stripeRefundProvider(async (url, init = {}) => {
    if (String(url).includes("payment_intents")) {
      return new Headers(init.headers).has("Stripe-Account")
        ? Response.json({
          error: { code: "resource_missing", message: "Not in this account" },
        }, { status: 404 })
        : Response.json({ transfer_data: { destination: "acct_original" } });
    }
    if (init.method === "POST") {
      sent = init;
      return Response.json(result);
    }
    return Response.json({ data: [], has_more: false });
  });
  await adapter.find(request);
  await adapter.create(request);
  assertEquals(new Headers(sent.headers).has("Stripe-Account"), false);
  assertEquals((sent.body as URLSearchParams).get("reverse_transfer"), "true");
});
Deno.test("historical charge with a different destination is refused", async () => {
  Deno.env.set("STRIPE_SECRET_KEY", "sk_test_fixture");
  const adapter = stripeRefundProvider(async (_url, init = {}) =>
    new Headers(init.headers).has("Stripe-Account")
      ? Response.json({ error: { code: "resource_missing" } }, { status: 404 })
      : Response.json({ transfer_data: { destination: "acct_wrong" } })
  );
  await assertRejects(() => adapter.find(request), Error, "does not match");
});
Deno.test("lookup paginates to find the previous refund by request ID", async () => {
  Deno.env.set("STRIPE_SECRET_KEY", "sk_test_fixture");
  const adapter = stripeRefundProvider(async (url) => {
    const address = String(url);
    if (address.includes("payment_intents")) {
      return Response.json({ id: "pi_test" });
    }
    return Response.json(
      address.includes("starting_after")
        ? {
          data: [{
            ...result,
            metadata: { ringmaster_refund_id: "refund-test" },
          }],
          has_more: false,
        }
        : { data: [{ id: "re_previous", metadata: {} }], has_more: true },
    );
  });
  assertEquals((await adapter.find(request))?.id, "re_test");
});
