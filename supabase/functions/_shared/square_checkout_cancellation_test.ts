import { cancelUnpaidSquareLink } from "./square_checkout_cancellation.ts";
import { SquareRequestError } from "./square.ts";

function fixture(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
  deletionError?: Error,
) {
  const calls: string[] = [];
  let reads = 0;
  return {
    calls,
    request: async (path: string, _token: string, init: RequestInit = {}) => {
      calls.push(`${init.method ?? "GET"} ${path}`);
      if (init.method === "DELETE") {
        if (deletionError) throw deletionError;
        return { id: "link", cancelled_order_id: "order" };
      }
      return { order: { id: "order", ...(++reads === 1 ? before : after) } };
    },
  };
}
async function rejects(run: () => Promise<unknown>, message: string) {
  try {
    await run();
  } catch (error) {
    if (String(error).includes(message)) return;
    throw error;
  }
  throw new Error(`Expected rejection containing ${message}`);
}
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("unpaid checkout is deleted and its exact order is rechecked before unlocking", async () => {
  const f = fixture({ state: "OPEN" }, { state: "CANCELED" });
  await cancelUnpaidSquareLink("order", "link", "test", f.request);
  equal(f.calls, [
    "GET /v2/orders/order",
    "DELETE /v2/online-checkout/payment-links/link",
    "GET /v2/orders/order",
  ]);
});
for (
  const order of [{ state: "COMPLETED" }, {
    state: "OPEN",
    tenders: [{ payment_id: "payment" }],
  }]
) {
  Deno.test(`paid/processing order cannot be canceled: ${JSON.stringify(order)}`, async () => {
    const f = fixture(order, { state: "CANCELED" });
    await rejects(
      () => cancelUnpaidSquareLink("order", "link", "test", f.request),
      "payment in progress or completed",
    );
    equal(f.calls.length, 1);
  });
}
Deno.test("a payment racing link cancellation keeps the cart locked", async () => {
  const f = fixture({ state: "OPEN" }, {
    state: "COMPLETED",
    tenders: [{ payment_id: "paid" }],
  });
  await rejects(
    () => cancelUnpaidSquareLink("order", "link", "test", f.request),
    "payment in progress or completed",
  );
});
Deno.test("missing link is insufficient unless its order is confirmed canceled", async () => {
  const f = fixture(
    { state: "OPEN" },
    { state: "OPEN" },
    new SquareRequestError("Missing", 404, "NOT_FOUND"),
  );
  await rejects(
    () => cancelUnpaidSquareLink("order", "link", "test", f.request),
    "not confirmed cancellation",
  );
});
Deno.test("retry after a deleted link recovers only a canceled order", async () => {
  const f = fixture(
    { state: "OPEN" },
    { state: "CANCELED" },
    new SquareRequestError("Missing", 404, "NOT_FOUND"),
  );
  await cancelUnpaidSquareLink("order", "link", "test", f.request);
});
Deno.test("already canceled order recovery is idempotent", async () => {
  const f = fixture({ state: "CANCELED" }, { state: "CANCELED" });
  await cancelUnpaidSquareLink("order", "link", "test", f.request);
  equal(f.calls.length, 2);
});
Deno.test("Square failure keeps cart locked", async () => {
  const f = fixture(
    { state: "OPEN" },
    { state: "CANCELED" },
    new SquareRequestError("Unavailable", 503, "INTERNAL_SERVER_ERROR"),
  );
  await rejects(
    () => cancelUnpaidSquareLink("order", "link", "test", f.request),
    "Unavailable",
  );
});
Deno.test("wrong order identity and missing link IDs fail closed", async () => {
  const f = fixture({ id: "other", state: "OPEN" }, { state: "CANCELED" });
  await rejects(
    () => cancelUnpaidSquareLink("order", "link", "test", f.request),
    "Unable to verify",
  );
  await rejects(
    () => cancelUnpaidSquareLink("order", "", "test", f.request),
    "incomplete",
  );
});
