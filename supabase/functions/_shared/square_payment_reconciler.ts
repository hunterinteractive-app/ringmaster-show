import { SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  finalizePaidCart,
  markPaymentAttemptTerminal,
  setProviderPaymentState,
} from "./payment.ts";
import { squareGet } from "./square.ts";
import { loadSquareAuthorization } from "./square_credentials.ts";
import type { SquareAuthorization } from "./square_credentials.ts";

export type SquarePaymentAttempt = {
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

export type SquarePaymentLookup = {
  payment: Record<string, unknown>;
  authorization: SquareAuthorization;
};

export type SquareReconciliationResult = {
  paymentSessionId: string;
  cartId: string;
  providerOrderId: string;
  providerPaymentId: string;
  paymentStatus: string;
  processed: boolean;
  finalized: boolean;
  alreadyFinalized: boolean;
};

const attemptColumns =
  "id,show_id,cart_id,provider,provider_order_id,provider_payment_id," +
  "expected_amount_cents,expected_currency,platform_fee_cents,attempt_status,metadata";

export async function loadSquarePaymentAttempt(
  client: SupabaseClient,
  paymentSessionId: string,
): Promise<SquarePaymentAttempt> {
  const result = await client.from("show_payment_sessions")
    .select(attemptColumns).eq("id", paymentSessionId).maybeSingle();
  if (result.error || !result.data) {
    throw new Error("Square payment attempt not found.");
  }
  const attempt = result.data as unknown as SquarePaymentAttempt;
  if (attempt.provider !== "square") {
    throw new Error("Payment session is not a Square attempt.");
  }
  if (!attempt.provider_order_id) {
    throw new Error("Square payment attempt is missing its order ID.");
  }
  return attempt;
}

export async function findSquarePaymentAttempt(
  client: SupabaseClient,
  args: {
    providerPaymentId?: string | null;
    providerOrderId?: string | null;
    paymentSessionId?: string | null;
  },
): Promise<SquarePaymentAttempt | null> {
  const lookups: Array<[string, string | null | undefined]> = [
    ["provider_payment_id", args.providerPaymentId],
    ["provider_order_id", args.providerOrderId],
    ["id", args.paymentSessionId],
  ];
  for (const [column, value] of lookups) {
    if (!value) continue;
    const result = await client.from("show_payment_sessions")
      .select(attemptColumns).eq("provider", "square")
      .eq(column, value).maybeSingle();
    if (result.error) {
      throw new Error("Unable to locate Square payment attempt.");
    }
    if (result.data) return result.data as unknown as SquarePaymentAttempt;
  }
  return null;
}

export async function retrieveSquarePaymentForAttempt(
  client: SupabaseClient,
  attempt: SquarePaymentAttempt,
  providerPaymentId?: string | null,
): Promise<SquarePaymentLookup | null> {
  if (attempt.provider !== "square" || !attempt.provider_order_id) {
    throw new Error("Square payment attempt is missing its order ID.");
  }
  const authorization = await loadSquareAuthorization(
    client,
    attempt.show_id,
    { requireReady: false },
  );

  if (providerPaymentId) {
    const result = await squareGet(
      `/v2/payments/${encodeURIComponent(providerPaymentId)}`,
      authorization.accessToken,
    );
    const payment = objectOrNull(result.payment);
    if (!payment || text(payment.id) !== providerPaymentId) {
      throw new Error("Square payment was not found.");
    }
    return { payment, authorization };
  }

  const orderResult = await squareGet(
    `/v2/orders/${encodeURIComponent(attempt.provider_order_id)}`,
    authorization.accessToken,
  );
  const order = objectOrNull(orderResult.order);
  if (!order || text(order.id) !== attempt.provider_order_id) {
    throw new Error("Square order was not found.");
  }
  const tenders = Array.isArray(order.tenders) ? order.tenders : [];
  const paymentIds = [
    ...new Set(
      tenders.map((tender) => text(objectOrNull(tender)?.payment_id)).filter(
        (value): value is string => value != null,
      ),
    ),
  ];
  let fallback: Record<string, unknown> | null = null;
  for (const paymentId of paymentIds) {
    const paymentResult = await squareGet(
      `/v2/payments/${encodeURIComponent(paymentId)}`,
      authorization.accessToken,
    );
    const payment = objectOrNull(paymentResult.payment);
    if (!payment || text(payment.order_id) !== attempt.provider_order_id) {
      continue;
    }
    fallback ??= payment;
    if (String(payment.status ?? "").toUpperCase() === "COMPLETED") {
      return { payment, authorization };
    }
  }
  return fallback ? { payment: fallback, authorization } : null;
}

export async function reconcileSquarePayment(
  client: SupabaseClient,
  args: {
    attempt: SquarePaymentAttempt;
    payment: Record<string, unknown>;
    authorization?: SquareAuthorization;
    requireCompleted?: boolean;
  },
): Promise<SquareReconciliationResult> {
  const { attempt, payment } = args;
  if (
    ["failed", "cancelled", "expired", "superseded"].includes(
      attempt.attempt_status,
    )
  ) {
    throw new Error("Square payment attempt is terminal.");
  }
  const authorization = args.authorization ?? await loadSquareAuthorization(
    client,
    attempt.show_id,
    { requireReady: false },
  );
  validateSquarePayment(
    payment,
    attempt,
    authorization,
    args.requireCompleted === true,
  );
  const providerPaymentId = requiredText(payment.id, "Square payment ID");
  const paymentStatus = String(payment.status ?? "").toUpperCase();

  let processed = true;
  let finalized = false;
  let alreadyFinalized = false;
  if (paymentStatus === "COMPLETED") {
    await setProviderPaymentState(client, {
      paymentSessionId: attempt.id,
      provider: "square",
      providerPaymentId,
      providerStatus: "COMPLETED",
    });
    const result = await finalizePaidCart(client, {
      cartId: attempt.cart_id,
      paymentSessionId: attempt.id,
      provider: "square",
      providerPaymentId,
      amountCents: attempt.expected_amount_cents,
      currency: attempt.expected_currency,
    });
    finalized = result.finalized === true;
    alreadyFinalized = result.already_finalized === true;
  } else if (paymentStatus === "PENDING" || paymentStatus === "APPROVED") {
    await setProviderPaymentState(client, {
      paymentSessionId: attempt.id,
      provider: "square",
      providerPaymentId,
      providerStatus: paymentStatus,
    });
  } else if (paymentStatus === "FAILED" || paymentStatus === "CANCELED") {
    await markPaymentAttemptTerminal(client, {
      paymentSessionId: attempt.id,
      provider: "square",
      status: paymentStatus === "FAILED" ? "failed" : "cancelled",
      failureCode: `square_${paymentStatus.toLowerCase()}`,
      failureMessage: `Square payment ${paymentStatus.toLowerCase()}.`,
      providerPaymentId,
    });
  } else {
    processed = false;
  }

  return {
    paymentSessionId: attempt.id,
    cartId: attempt.cart_id,
    providerOrderId: attempt.provider_order_id!,
    providerPaymentId,
    paymentStatus,
    processed,
    finalized,
    alreadyFinalized,
  };
}

export function validateSquarePayment(
  payment: Record<string, unknown>,
  attempt: SquarePaymentAttempt,
  authorization: SquareAuthorization,
  requireCompleted = false,
): void {
  if (attempt.provider !== "square" || !attempt.provider_order_id) {
    throw new Error("Payment session is not a valid Square attempt.");
  }
  if (text(payment.order_id) !== attempt.provider_order_id) {
    throw new Error("Square order does not match the saved payment attempt.");
  }
  if (
    requireCompleted &&
    String(payment.status ?? "").toUpperCase() !== "COMPLETED"
  ) {
    throw new Error("Square payment is not completed.");
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
  if (String(payment.location_id ?? "") !== authorization.locationId) {
    throw new Error("Square location does not match the connected account.");
  }
  if (
    payment.merchant_id &&
    String(payment.merchant_id) !== authorization.merchantId
  ) {
    throw new Error("Square merchant does not match the connected account.");
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

function objectOrNull(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function text(value: unknown): string | null {
  const result = String(value ?? "").trim();
  return result ? result : null;
}

function requiredText(value: unknown, label: string): string {
  const result = text(value);
  if (!result) throw new Error(`${label} is missing.`);
  return result;
}
