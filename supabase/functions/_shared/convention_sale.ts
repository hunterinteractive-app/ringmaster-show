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
  return readCheckoutMeasurement(body, now, 250);
}

function readCheckoutMeasurement(
  body: Record<string, unknown>,
  now: number,
  maxAccuracy: number,
) {
  const { latitude, longitude, accuracy, measured_at } = body;
  if (
    typeof latitude !== "number" || !Number.isFinite(latitude) ||
    Math.abs(latitude) > 90 ||
    typeof longitude !== "number" || !Number.isFinite(longitude) ||
    Math.abs(longitude) > 180 ||
    typeof accuracy !== "number" || !Number.isFinite(accuracy) ||
    accuracy < 0 || accuracy > maxAccuracy ||
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

/** Explains a rejected check; it never approves checkout or stores coordinates. */
export function conventionLocationFailure(
  body: Record<string, unknown>,
  settings: Record<string, unknown> | null,
  now = Date.now(),
) {
  let outside = false;
  try {
    // A coarse reading cannot qualify for checkout, but its entire uncertainty
    // circle can still be clearly outside the configured convention radius.
    const point = readCheckoutMeasurement(body, now, Infinity);
    const latitude = settings?.latitude;
    const longitude = settings?.longitude;
    const miles = settings?.radius_miles;
    if (
      typeof latitude === "number" && Number.isFinite(latitude) &&
      Math.abs(latitude) <= 90 &&
      typeof longitude === "number" && Number.isFinite(longitude) &&
      Math.abs(longitude) <= 180 &&
      typeof miles === "number" && Number.isFinite(miles) && miles > 0
    ) {
      const radians = (degrees: number) => degrees * Math.PI / 180;
      const haversine = Math.sin(radians(point.latitude - latitude) / 2) ** 2 +
        Math.cos(radians(latitude)) * Math.cos(radians(point.latitude)) *
          Math.sin(radians(point.longitude - longitude) / 2) ** 2;
      // Match the database's Earth diameter and miles-to-meters conversion.
      const distance = 12742017.6 *
        Math.asin(Math.sqrt(Math.min(1, Math.max(0, haversine))));
      outside = distance - point.accuracy > miles * 1609.344;
    }
  } catch {
    // Invalid or stale measurements cannot establish that someone is outside.
  }
  return {
    code: outside ? "outside_sale_area" : "location_unconfirmed",
    error: outside
      ? "Your location is outside the allowed radius. You need to be inside the sale area at the showroom to place this order. If you continue to have issues, please stop by the booth."
      : "We couldn't confirm your location inside the sale area. You need to be in the showroom to place this order. Please try again with precise location enabled. If you continue to have issues, please stop by the booth.",
  };
}

export function conventionSecretaryQuestions() {
  return [
    {
      key: "showsecretaryname",
      label: { type: "custom" as const, custom: "Show Secretary Name" },
      type: "text" as const,
      optional: false,
      text: { minimum_length: 1, maximum_length: 255 },
    },
    {
      key: "showsecretaryemail",
      label: { type: "custom" as const, custom: "Show Secretary Email" },
      type: "text" as const,
      optional: false,
      text: { minimum_length: 3, maximum_length: 254 },
    },
  ];
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
  custom_fields?: { key: string; text?: { value?: string | null } | null }[];
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
  const params = {
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
  const recipientMode = session.metadata?.convention_recipient;
  if (recipientMode === undefined) return params;
  if (recipientMode !== "secretary") {
    throw new Error("Unknown convention recipient mode");
  }
  const name = session.custom_fields?.find((f) => f.key === "showsecretaryname")
    ?.text?.value?.trim();
  const email = session.custom_fields?.find((f) =>
    f.key === "showsecretaryemail"
  )?.text?.value?.trim().toLowerCase();
  if (
    !name || name.length > 255 || /[\x00-\x1f\x7f]/.test(name) || !email ||
    email.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    throw new Error("A valid Show Secretary Name and Email are required");
  }
  return { ...params, p_secretary_name: name, p_secretary_email: email };
}
