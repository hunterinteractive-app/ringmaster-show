export const conventionPlans = {
  single_show: {
    paymentLink: "plink_1T8AUlLAhl5IBJ5keevfZsgC",
    label: "1 show token",
  },
  four_shows: {
    paymentLink: "plink_1T8AZ0LAhl5IBJ5k0juABLKy",
    label: "4 show tokens",
  },
  unlimited: {
    paymentLink: "plink_1T8AW1LAhl5IBJ5kEpmoJxvU",
    label: "12 months unlimited",
  },
} as const;
export type ConventionPlan = keyof typeof conventionPlans;
export function isConventionPlan(value: unknown): value is ConventionPlan {
  return typeof value === "string" && Object.hasOwn(conventionPlans, value);
}
export function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

export function checkoutMeasurement(
  body: Record<string, unknown>,
  now = Date.now(),
) {
  const { latitude, longitude, accuracy, measured_at } = body;
  if (
    typeof latitude !== "number" || !Number.isFinite(latitude) ||
    Math.abs(latitude) > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) ||
    Math.abs(longitude) > 180 ||
    typeof accuracy !== "number" || !Number.isFinite(accuracy) ||
    accuracy < 0 || accuracy > 250 ||
    typeof measured_at !== "string" ||
    !Number.isFinite(Date.parse(measured_at)) ||
    Date.parse(measured_at) < now - 60_000 ||
    Date.parse(measured_at) > now + 30_000
  ) {
    throw new Error(
      "A fresh, accurate location reading is required. Retry or visit the booth for help.",
    );
  }
  return { latitude, longitude, accuracy, measured_at };
}

type PurchaseSession = {
  id: string;
  status: string | null;
  payment_status: string;
  livemode: boolean;
  created: number;
  amount_subtotal: number | null;
  amount_total: number | null;
  currency: string | null;
  client_reference_id?: string | null;
  metadata: Record<string, string> | null;
  line_items?: {
    data: {
      quantity: number | null;
      price?: {
        id: string;
        unit_amount?: number | null;
        tax_behavior?: string | null;
      } | null;
    }[];
    has_more?: boolean;
  };
};
export function conventionFulfillmentParams(session: PurchaseSession) {
  const claimId = session.metadata?.convention_claim_id;
  if (
    !isUuid(claimId) || session.client_reference_id !== claimId ||
    session.status !== "complete" || session.payment_status !== "paid" ||
    session.line_items?.has_more || session.line_items?.data.length !== 1 ||
    session.line_items.data[0].quantity !== 1 ||
    !session.line_items.data[0].price?.id ||
    !Number.isSafeInteger(session.amount_subtotal) ||
    (session.amount_subtotal ?? 0) <= 0 ||
    !Number.isSafeInteger(session.amount_total) ||
    (session.amount_total ?? 0) <= 0 ||
    (session.amount_total ?? 0) < (session.amount_subtotal ?? 0) ||
    !Number.isSafeInteger(session.line_items.data[0].price.unit_amount) ||
    (session.line_items.data[0].price.unit_amount ?? 0) <= 0 ||
    !session.currency || !Number.isSafeInteger(session.created)
  ) {
    throw new Error("Convention payment does not match its offer");
  }
  return {
    p_claim_id: claimId,
    p_session_id: session.id,
    p_price_id: session.line_items.data[0].price.id,
    // An inclusive price's subtotal excludes the embedded tax. Exclusive
    // prices are verified against subtotal; inclusive prices against total.
    p_amount_cents:
      session.line_items.data[0].price.tax_behavior === "inclusive"
        ? session.amount_total
        : session.amount_subtotal,
    p_currency: session.currency,
    p_livemode: session.livemode,
    p_checkout_created: new Date(session.created * 1000).toISOString(),
  };
}
