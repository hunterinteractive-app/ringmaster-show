import { SupabaseClient } from "npm:@supabase/supabase-js@2";

export type PaymentProvider = "stripe" | "square" | "paypal";

export type QuoteSnapshot = {
  version: number;
  cart_id: string;
  show_id: string;
  show_name: string;
  user_id: string;
  provider: PaymentProvider;
  currency: string;
  show_balance_total_cents: number;
  online_fee_cents: number;
  platform_fee_cents: number;
  expected_amount_cents: number;
  online_payment_fee_mode: string;
  online_payment_fee_label: string;
  online_payment_fee_description: string;
  balances: Array<Record<string, unknown>>;
};

export type PaymentAttempt = {
  reused: boolean;
  payment_session_id: string;
  idempotency_key: string;
  quote_hash: string;
  quote: QuoteSnapshot;
  provider_session_id?: string | null;
  checkout_url?: string | null;
  expires_at?: string | null;
};

export type RecordedPaymentEvent = {
  event_row_id: string;
  duplicate: boolean;
  claimed: boolean;
  already_processed: boolean;
  processing_status: string;
};

export type PaymentFeeQuote = {
  baseTotalCents: number;
  onlineFeeCents: number;
  expectedAmountCents: number;
  platformFeeCents: number;
  platformFeeRate: number;
  processingFeeRate: number;
  processingFeeFixedCents: number;
};

export function calculatePaymentFeeQuote(args: {
  baseTotalCents: number;
  passFeeToExhibitor: boolean;
  platformFeePercent: number;
  processingFeePercent: number;
  processingFeeFixedCents: number;
}): PaymentFeeQuote {
  const platformRate = normalizePercent(args.platformFeePercent);
  const processingRate = normalizePercent(args.processingFeePercent);
  const fixedCents = Math.max(Math.round(args.processingFeeFixedCents), 0);
  const combinedRate = platformRate + processingRate;
  if (args.baseTotalCents <= 0) {
    throw new Error("Checkout total must be greater than zero.");
  }
  if (platformRate < 0 || processingRate < 0 || combinedRate >= 1) {
    throw new Error("Payment fee configuration is invalid.");
  }

  let onlineFeeCents = 0;
  if (args.passFeeToExhibitor) {
    onlineFeeCents = Math.max(
      Math.ceil(
        (args.baseTotalCents + fixedCents) / (1 - combinedRate) -
          args.baseTotalCents,
      ),
      0,
    );
    for (let i = 0; i < 10; i++) {
      const total = args.baseTotalCents + onlineFeeCents;
      const required = Math.round(total * platformRate) +
        Math.ceil(total * processingRate + fixedCents);
      if (onlineFeeCents >= required) break;
      onlineFeeCents = required;
    }
  }

  const expectedAmountCents = args.baseTotalCents + onlineFeeCents;
  let platformFeeCents = Math.round(expectedAmountCents * platformRate);
  if (platformFeeCents < 1 && platformRate > 0) platformFeeCents = 1;
  if (platformFeeCents >= expectedAmountCents) {
    throw new Error("Platform fee must be less than the charged amount.");
  }
  return {
    baseTotalCents: args.baseTotalCents,
    onlineFeeCents,
    expectedAmountCents,
    platformFeeCents,
    platformFeeRate: platformRate,
    processingFeeRate: processingRate,
    processingFeeFixedCents: fixedCents,
  };
}

function normalizePercent(value: number): number {
  return value > 1 ? value / 100 : value;
}

export async function createPaymentQuoteAttempt(
  client: SupabaseClient,
  args: {
    cartId: string;
    userId: string;
    provider: PaymentProvider;
    platformFeeDefaultPercent: number;
    processingFeePercent: number;
    processingFeeFixedCents: number;
  },
): Promise<PaymentAttempt> {
  const { data, error } = await client.rpc("create_payment_quote_attempt", {
    p_cart_id: args.cartId,
    p_user_id: args.userId,
    p_provider: args.provider,
    p_platform_fee_default_percent: args.platformFeeDefaultPercent,
    p_processing_fee_percent: args.processingFeePercent,
    p_processing_fee_fixed_cents: args.processingFeeFixedCents,
  });
  if (error) throw new Error(error.message);
  return requireObject(data, "Payment quote") as unknown as PaymentAttempt;
}

export async function attachProviderSession(
  client: SupabaseClient,
  args: {
    paymentSessionId: string;
    provider: PaymentProvider;
    providerSessionId: string;
    checkoutUrl: string;
    expiresAt?: string | null;
  },
): Promise<void> {
  const { error } = await client.rpc("attach_provider_payment_session", {
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_provider_session_id: args.providerSessionId,
    p_checkout_url: args.checkoutUrl,
    p_expires_at: args.expiresAt ?? null,
  });
  if (error) throw new Error(error.message);
}

export async function attachProviderHostedCheckout(
  client: SupabaseClient,
  args: {
    paymentSessionId: string;
    provider: PaymentProvider;
    providerSessionId: string;
    providerOrderId: string;
    checkoutUrl: string;
    providerMetadata?: Record<string, unknown>;
  },
): Promise<void> {
  if (
    !args.providerSessionId.trim() || !args.providerOrderId.trim() ||
    !args.checkoutUrl.trim()
  ) {
    throw new Error("Hosted checkout link, order, and URL are required.");
  }
  const { data, error } = await client.rpc("attach_provider_hosted_checkout", {
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_provider_session_id: args.providerSessionId,
    p_provider_order_id: args.providerOrderId,
    p_checkout_url: args.checkoutUrl,
    p_provider_metadata: args.providerMetadata ?? {},
  });
  if (error) throw new Error(error.message);
  const attached = requireObject(data, "Hosted checkout attachment");
  if (
    attached.attached !== true ||
    attached.provider_session_id !== args.providerSessionId ||
    attached.provider_order_id !== args.providerOrderId
  ) {
    throw new Error("Hosted checkout identifiers were not persisted.");
  }
}

export async function supersedeProviderCheckout(
  client: SupabaseClient,
  args: {
    paymentSessionId: string;
    provider: PaymentProvider;
    linkDeactivated: boolean;
  },
): Promise<void> {
  const { error } = await client.rpc("supersede_provider_checkout", {
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_link_deactivated: args.linkDeactivated,
  });
  if (error) throw new Error(error.message);
}

export async function claimPaymentAttemptClientKey(
  client: SupabaseClient,
  args: {
    paymentSessionId: string;
    provider: PaymentProvider;
    clientAttemptKeyHash: string;
  },
): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc("claim_payment_attempt_client_key", {
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_client_attempt_key_hash: args.clientAttemptKeyHash,
  });
  if (error) throw new Error(error.message);
  return requireObject(data, "Payment attempt claim");
}

export async function setProviderPaymentState(
  client: SupabaseClient,
  args: {
    paymentSessionId: string;
    provider: PaymentProvider;
    providerPaymentId: string;
    providerStatus: "PENDING" | "APPROVED" | "COMPLETED";
  },
): Promise<void> {
  const { error } = await client.rpc("set_provider_payment_state", {
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_provider_payment_id: args.providerPaymentId,
    p_provider_status: args.providerStatus,
  });
  if (error) throw new Error(error.message);
}

export async function markPaymentAttemptTerminal(
  client: SupabaseClient,
  args: {
    paymentSessionId: string;
    provider: PaymentProvider;
    status: "failed" | "cancelled" | "expired" | "superseded";
    failureCode?: string | null;
    failureMessage?: string | null;
    providerPaymentId?: string | null;
  },
): Promise<void> {
  const { error } = await client.rpc("mark_payment_attempt_terminal", {
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_status: args.status,
    p_failure_code: args.failureCode ?? null,
    p_failure_message: args.failureMessage ?? null,
    p_provider_payment_id: args.providerPaymentId ?? null,
  });
  if (error) throw new Error(error.message);
}

export async function recordPaymentEvent(
  client: SupabaseClient,
  args: {
    provider: PaymentProvider;
    eventId: string;
    eventType: string;
    payload?: Record<string, unknown>;
    paymentSessionId?: string | null;
    providerPaymentId?: string | null;
  },
): Promise<RecordedPaymentEvent> {
  const { data, error } = await client.rpc("record_payment_event", {
    p_provider: args.provider,
    p_event_id: args.eventId,
    p_event_type: args.eventType,
    p_payload: args.payload ?? {},
    p_payment_session_id: args.paymentSessionId ?? null,
    p_provider_payment_id: args.providerPaymentId ?? null,
  });
  if (error) throw new Error(error.message);
  return requireObject(
    data,
    "Payment event",
  ) as unknown as RecordedPaymentEvent;
}

export async function setPaymentEventStatus(
  client: SupabaseClient,
  args: {
    provider: PaymentProvider;
    eventId: string;
    status: "received" | "processing" | "processed" | "ignored" | "failed";
    error?: string | null;
    paymentSessionId?: string | null;
    providerPaymentId?: string | null;
  },
): Promise<void> {
  const { error } = await client.rpc("set_payment_event_status", {
    p_provider: args.provider,
    p_event_id: args.eventId,
    p_processing_status: args.status,
    p_processing_error: args.error ?? null,
    p_payment_session_id: args.paymentSessionId ?? null,
    p_provider_payment_id: args.providerPaymentId ?? null,
  });
  if (error) throw new Error(error.message);
}

export async function finalizePaidCart(
  client: SupabaseClient,
  args: {
    cartId: string;
    paymentSessionId: string;
    provider: PaymentProvider;
    providerPaymentId: string;
    amountCents: number;
    currency: string;
  },
): Promise<Record<string, unknown>> {
  const { data, error } = await client.rpc("finalize_entry_cart_paid", {
    p_cart_id: args.cartId,
    p_payment_session_id: args.paymentSessionId,
    p_provider: args.provider,
    p_provider_payment_id: args.providerPaymentId,
    p_amount_cents: args.amountCents,
    p_currency: args.currency,
  });
  if (error) throw new Error(error.message);
  return requireObject(data, "Payment finalization");
}

function requireObject(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} returned an invalid response.`);
  }
  return value as Record<string, unknown>;
}
