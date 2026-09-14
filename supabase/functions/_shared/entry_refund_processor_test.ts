import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  EntryRefund,
  processEntryRefund,
  ProviderRefund,
  RefundProvider,
  RefundRejected,
} from "./entry_refund_processor.ts";

const now = Date.now();
const request: EntryRefund = {
  id: "test-id",
  show_id: "show",
  exhibitor_id: "ex",
  provider: "stripe",
  provider_payment_id: "pi_test",
  provider_account_id: "acct_test",
  provider_refund_id: null,
  currency: "usd",
  entry_amount_cents: 1000,
  online_fee_cents: 50,
  reason: "Entry canceled",
  status: "prepared",
  attempted_at: new Date(now).toISOString(),
};
const success: ProviderRefund = {
  id: "re_test",
  paymentId: "pi_test",
  amountCents: 1050,
  currency: "usd",
  status: "succeeded",
};

function harness(overrides: Partial<RefundProvider> = {}) {
  const writes: unknown[][] = [];
  let creates = 0;
  const provider: RefundProvider = {
    find: async () => null,
    create: async () => {
      creates++;
      return success;
    },
    ...overrides,
  };
  const save = async (...args: [string, string | null, string | null]) => {
    writes.push(args);
    return { status: args[0] };
  };
  return { provider, save, writes, creates: () => creates };
}
Deno.test("successful refund records the exact provider reference", async () => {
  const h = harness();
  await processEntryRefund(request, h.provider, h.save, now);
  assertEquals(h.writes, [["succeeded", "re_test", null]]);
  assertEquals(h.creates(), 1);
});
Deno.test("pending provider refund does not report completion", async () => {
  const h = harness({
    create: async () => ({ ...success, status: "pending" }),
  });
  await processEntryRefund(request, h.provider, h.save, now);
  assertEquals(h.writes, [["pending", "re_test", null]]);
});
Deno.test("retry finds the original refund without creating another", async () => {
  const h = harness({ find: async () => success });
  await processEntryRefund(request, h.provider, h.save, now);
  assertEquals(h.creates(), 0);
});
Deno.test("unknown network outcome stays reserved for reconciliation", async () => {
  const h = harness({
    create: async () => {
      throw new Error("Connection lost");
    },
  });
  await processEntryRefund(request, h.provider, h.save, now);
  assertEquals(h.writes, [["needs_review", null, "Connection lost"]]);
});
Deno.test("definitive rejection releases the request as failed", async () => {
  const h = harness({
    create: async () => {
      throw new RefundRejected("Already refunded");
    },
  });
  await processEntryRefund(request, h.provider, h.save, now);
  assertEquals(h.writes, [["failed", null, "Already refunded"]]);
});
Deno.test("expired idempotency window cannot create a new refund", async () => {
  const h = harness();
  await processEntryRefund(
    request,
    h.provider,
    h.save,
    now + 25 * 60 * 60 * 1000,
  );
  assertEquals(h.creates(), 0);
  assertEquals(h.writes[0][0], "needs_review");
});
Deno.test("old request can reconcile an existing refund after idempotency window", async () => {
  const h = harness({ find: async () => success });
  await processEntryRefund(
    request,
    h.provider,
    h.save,
    now + 25 * 60 * 60 * 1000,
  );
  assertEquals(h.writes[0][0], "succeeded");
  assertEquals(h.creates(), 0);
});
Deno.test("mismatched amount, currency, payment or reference cannot complete", async () => {
  for (
    const modified of [{ amountCents: 1000 }, { currency: "cad" }, {
      paymentId: "pi_other",
    }, { id: "re_other" }]
  ) {
    const h = harness({ find: async () => ({ ...success, ...modified }) });
    await processEntryRefund(
      { ...request, provider_refund_id: "re_test" },
      h.provider,
      h.save,
      now,
    );
    assertEquals(h.writes[0][0], "needs_review");
  }
});
Deno.test("known provider ID missing never triggers a replacement", async () => {
  const h = harness();
  await processEntryRefund(
    { ...request, provider_refund_id: "re_test" },
    h.provider,
    h.save,
    now,
  );
  assertEquals(h.creates(), 0);
  assertEquals(h.writes[0][0], "needs_review");
});
Deno.test("database error after provider success remains retryable", async () => {
  const h = harness();
  await assertRejects(
    () =>
      processEntryRefund(request, h.provider, async () => {
        throw new Error("Database unavailable");
      }, now),
    Error,
    "Database unavailable",
  );
});
Deno.test("manual receipt never calls a payment provider", async () => {
  const h = harness({
    find: async () => {
      throw new Error("Must not call");
    },
  });
  await processEntryRefund(
    { ...request, provider: "manual" },
    h.provider,
    h.save,
    now,
  );
  assertEquals(h.writes, [["succeeded", null, null]]);
  assertEquals(h.creates(), 0);
});
Deno.test("completed refunds cannot be replayed", async () => {
  const h = harness();
  await processEntryRefund(
    { ...request, status: "succeeded" },
    h.provider,
    h.save,
    now,
  );
  assertEquals(h.writes, []);
  assertEquals(h.creates(), 0);
});
