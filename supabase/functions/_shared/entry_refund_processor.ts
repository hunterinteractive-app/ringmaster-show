/** Provider-independent state machine. Persist the request before invoking it;
 * retries use its durable UUID, including after an ambiguous network failure. */
export type EntryRefund = {
  id: string;
  show_id: string;
  exhibitor_id: string;
  provider: string;
  provider_payment_id: string | null;
  provider_account_id: string | null;
  provider_refund_id: string | null;
  currency: string;
  entry_amount_cents: number;
  online_fee_cents: number;
  reason: string;
  status: string;
  attempted_at: string | null;
};

export type ProviderRefund = {
  id: string;
  paymentId: string;
  amountCents: number;
  currency: string;
  status: "succeeded" | "pending" | "failed";
};

export type RefundProvider = {
  find(request: EntryRefund): Promise<ProviderRefund | null>;
  create(request: EntryRefund): Promise<ProviderRefund>;
};

export class RefundRejected extends Error {}

export async function processEntryRefund(
  request: EntryRefund,
  provider: RefundProvider,
  save: (
    status: string,
    reference: string | null,
    error: string | null,
  ) => Promise<unknown>,
  now = Date.now(),
): Promise<unknown> {
  if (["succeeded", "failed"].includes(request.status)) {
    return { id: request.id, status: request.status };
  }
  if (request.provider === "manual") return await save("succeeded", null, null);
  let result: ProviderRefund;
  try {
    const existing = await provider.find(request);
    if (!existing && request.provider_refund_id) {
      throw new Error(
        "The provider refund could not be retrieved. Check again before taking further action.",
      );
    }
    // Stripe may prune idempotency keys after 24 hours. Never create a second
    // refund after that window; keep searching for the original instead.
    const elapsed = now - Date.parse(request.attempted_at ?? "");
    if (
      !existing && (!Number.isFinite(elapsed) || elapsed > 20 * 60 * 60 * 1000)
    ) {
      return await save(
        "needs_review",
        null,
        "The original refund could not be confirmed. Review the original payment with the provider; another refund will not be issued automatically.",
      );
    }
    result = existing ?? await provider.create(request);
    if (
      !result.id || result.paymentId !== request.provider_payment_id ||
      result.amountCents !==
        request.entry_amount_cents + request.online_fee_cents ||
      result.currency.toLowerCase() !== request.currency.toLowerCase() ||
      (request.provider_refund_id && request.provider_refund_id !== result.id)
    ) {
      throw new Error(
        "The provider refund does not match this request. Review is required.",
      );
    }
  } catch (error) {
    // An unknown outcome is not a failed refund. Keep entries reserved and
    // reconcile using the same request, never a newly generated identifier.
    return await save(
      error instanceof RefundRejected ? "failed" : "needs_review",
      null,
      error instanceof Error
        ? error.message
        : "Refund status could not be confirmed.",
    );
  }
  // A database failure after provider success must escape to the caller. The
  // next reconciliation finds the same provider refund and retries accounting.
  return await save(
    result.status,
    result.id,
    result.status === "failed"
      ? "The provider declined or canceled the refund. Entries were not removed."
      : null,
  );
}
