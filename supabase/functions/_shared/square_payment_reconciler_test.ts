import type { SquareAuthorization } from "./square_credentials.ts";
import { validateSquarePayment } from "./square_payment_reconciler.ts";
import type { SquarePaymentAttempt } from "./square_payment_reconciler.ts";

const attempt: SquarePaymentAttempt = {
  id: "10c2ff2c-0b9d-42eb-a9ba-b4efe5154a4e",
  show_id: "0f432fe8-2be2-467a-842f-ff3777436992",
  cart_id: "0ef46a1b-907e-44f4-90b5-a8a92e81cc02",
  provider: "square",
  provider_order_id: "wxRNInUl92nmEcJJ1Q9ecXbTRaVZY",
  provider_payment_id: null,
  expected_amount_cents: 200,
  expected_currency: "usd",
  platform_fee_cents: 4,
  attempt_status: "pending",
  metadata: {
    square_environment: "sandbox",
    application_fee_sent_to_provider: false,
  },
};

const authorization: SquareAuthorization = {
  linkId: "sandbox-test-link",
  merchantId: "MLSYDRF5M517Q",
  locationId: "LBYVFYDST1F6C",
  currency: "usd",
  accessToken: "not-a-real-token",
};

const payment: Record<string, unknown> = {
  id: "7JeImKLxO1hCASm66Mk6lepcNyNZY",
  order_id: "wxRNInUl92nmEcJJ1Q9ecXbTRaVZY",
  status: "COMPLETED",
  amount_money: { amount: 200, currency: "USD" },
  merchant_id: "MLSYDRF5M517Q",
  location_id: "LBYVFYDST1F6C",
};

Deno.test("reported completed Square sandbox payment matches its exact attempt", () => {
  validateSquarePayment(payment, attempt, authorization, true);
  assertEquals(payment.id, "7JeImKLxO1hCASm66Mk6lepcNyNZY");
});

Deno.test("manual reconciliation rejects a non-completed Square payment", () => {
  assertThrows(
    () =>
      validateSquarePayment(
        { ...payment, status: "APPROVED" },
        attempt,
        authorization,
        true,
      ),
    Error,
    "Square payment is not completed",
  );
});

Deno.test("Square reconciliation rejects financial and account mismatches", () => {
  const cases: Array<[Record<string, unknown>, string]> = [
    [{ ...payment, amount_money: { amount: 201, currency: "USD" } }, "amount"],
    [
      { ...payment, amount_money: { amount: 200, currency: "EUR" } },
      "currency",
    ],
    [{ ...payment, location_id: "different-location" }, "location"],
    [{ ...payment, merchant_id: "different-merchant" }, "merchant"],
  ];
  for (const [candidate, expectedMessage] of cases) {
    assertThrows(
      () => validateSquarePayment(candidate, attempt, authorization, true),
      Error,
      expectedMessage,
    );
  }
});

Deno.test("production reconciliation requires the saved application fee", () => {
  const productionAttempt = {
    ...attempt,
    metadata: { application_fee_sent_to_provider: true },
  };
  validateSquarePayment(
    { ...payment, app_fee_money: { amount: 4, currency: "USD" } },
    productionAttempt,
    authorization,
    true,
  );
  assertThrows(
    () =>
      validateSquarePayment(
        { ...payment, app_fee_money: { amount: 3, currency: "USD" } },
        productionAttempt,
        authorization,
        true,
      ),
    Error,
    "application fee",
  );
});

Deno.test("Square reconciliation rejects a payment from another order", () => {
  assertThrows(
    () =>
      validateSquarePayment(
        { ...payment, order_id: "different-order" },
        attempt,
        authorization,
      ),
    Error,
    "Square order does not match",
  );
});

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(
      `Expected ${String(expected)}, received ${String(actual)}.`,
    );
  }
}

function assertThrows(
  callback: () => void,
  errorType: typeof Error,
  expectedMessage: string,
): void {
  try {
    callback();
  } catch (error) {
    if (error instanceof errorType && error.message.includes(expectedMessage)) {
      return;
    }
    throw error;
  }
  throw new Error("Expected callback to throw.");
}
