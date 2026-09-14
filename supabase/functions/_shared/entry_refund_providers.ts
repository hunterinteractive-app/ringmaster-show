import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  EntryRefund,
  ProviderRefund,
  RefundProvider,
  RefundRejected,
} from "./entry_refund_processor.ts";
import { loadSquareAuthorization } from "./square_credentials.ts";
import { squareRequest, SquareRequestError } from "./square.ts";

type Json = Record<string, any>;

export function stripeRefundProvider(
  fetcher: typeof fetch = fetch,
): RefundProvider {
  let destinationCharge = false;
  let account: string | null = null;
  async function api(path: string, init: RequestInit = {}): Promise<Json> {
    const key = Deno.env.get("STRIPE_SECRET_KEY");
    if (!key) throw new Error("Stripe is not configured for refunds.");
    const response = await fetcher(`https://api.stripe.com/v1${path}`, {
      ...init,
      signal: AbortSignal.timeout(25000),
      headers: {
        Authorization: `Bearer ${key}`,
        "Stripe-Version": "2024-04-10",
        ...(account ? { "Stripe-Account": account } : {}),
        ...init.headers,
      },
    });
    const data = await response.json();
    if (!response.ok) {
      const error = new Error(
        String(data.error?.message ?? "Stripe refund could not be confirmed."),
      );
      Object.assign(error, { code: data.error?.code, status: response.status });
      throw error;
    }
    return data;
  }
  async function scope(r: EntryRefund): Promise<void> {
    account = r.provider_account_id;
    if (!account) {
      throw new Error(
        "The original Stripe account is missing from this payment. Review the payment before refunding.",
      );
    }
    try {
      await api(
        `/payment_intents/${encodeURIComponent(r.provider_payment_id!)}`,
      );
    } catch (error) {
      if ((error as Json).code !== "resource_missing") throw error;
      // Older destination charges live on the platform account. Only accept
      // that fallback when Stripe confirms the saved connected destination.
      account = null;
      const intent = await api(
        `/payment_intents/${encodeURIComponent(r.provider_payment_id!)}`,
      );
      const destination = intent.transfer_data?.destination;
      if (
        (typeof destination === "string" ? destination : destination?.id) !==
          r.provider_account_id
      ) {
        throw new Error(
          "The original Stripe account does not match this payment.",
        );
      }
      destinationCharge = true;
    }
  }
  function read(data: Json): ProviderRefund {
    return {
      id: data.id,
      paymentId: typeof data.payment_intent === "string"
        ? data.payment_intent
        : data.payment_intent?.id,
      amountCents: data.amount,
      currency: data.currency,
      status: data.status === "succeeded"
        ? "succeeded"
        : ["failed", "canceled"].includes(data.status)
        ? "failed"
        : "pending",
    };
  }
  return {
    async find(r) {
      await scope(r);
      if (r.provider_refund_id) {
        return read(
          await api(`/refunds/${encodeURIComponent(r.provider_refund_id)}`),
        );
      }
      let cursor = "";
      do {
        const query = new URLSearchParams({
          payment_intent: r.provider_payment_id!,
          limit: "100",
        });
        if (cursor) query.set("starting_after", cursor);
        const page = await api(`/refunds?${query}`);
        const existing = page.data?.find((x: Json) =>
          x.metadata?.ringmaster_refund_id === r.id
        );
        if (existing) return read(existing);
        cursor = page.has_more ? page.data?.at(-1)?.id ?? "" : "";
      } while (cursor);
      return null;
    },
    async create(r) {
      const body = new URLSearchParams({
        payment_intent: r.provider_payment_id!,
        amount: String(r.entry_amount_cents + r.online_fee_cents),
        reason: "requested_by_customer",
        "metadata[ringmaster_refund_id]": r.id,
        "metadata[show_id]": r.show_id,
        refund_application_fee: String(r.online_fee_cents > 0),
      });
      if (destinationCharge) body.set("reverse_transfer", "true");
      try {
        return read(
          await api("/refunds", {
            method: "POST",
            body,
            headers: {
              "Content-Type": "application/x-www-form-urlencoded",
              "Idempotency-Key": `entry-refund:${r.id}`,
            },
          }),
        );
      } catch (error) {
        // The request is deterministically rejected, with no refund created.
        // Account/configuration failures and unknown errors stay recoverable.
        const e = error as Json;
        if (
          e.status === 400 &&
          [
            "amount_too_large",
            "amount_too_small",
            "charge_already_refunded",
            "charge_disputed",
          ].includes(e.code)
        ) {
          throw new RefundRejected(e.message);
        }
        throw error;
      }
    },
  };
}

export function squareRefundProvider(client: SupabaseClient): RefundProvider {
  let token = "";
  let payment: Json = {};
  function read(x: Json): ProviderRefund {
    return {
      id: x.id,
      paymentId: x.payment_id,
      amountCents: Number(x.amount_money?.amount),
      currency: x.amount_money?.currency,
      status: x.status === "COMPLETED"
        ? "succeeded"
        : ["FAILED", "REJECTED"].includes(x.status)
        ? "failed"
        : "pending",
    };
  }
  return {
    async find(r) {
      const authorization = await loadSquareAuthorization(client, r.show_id, {
        requireReady: false,
      });
      token = authorization.accessToken;
      payment = (await squareRequest(
        `/v2/payments/${encodeURIComponent(r.provider_payment_id!)}`,
        token,
      )).payment as Json;
      if (payment.location_id !== authorization.locationId) {
        throw new Error(
          "The original Square location does not match this payment.",
        );
      }
      const ids = r.provider_refund_id
        ? [r.provider_refund_id]
        : payment.refund_ids ?? [];
      for (const id of ids) {
        const refund =
          (await squareRequest(`/v2/refunds/${encodeURIComponent(id)}`, token))
            .refund as Json;
        if (
          r.provider_refund_id ||
          String(refund.reason ?? "").includes(`[RM ${r.id}]`)
        ) return read(refund);
      }
      return null;
    },
    async create(r) {
      const body: Json = {
        idempotency_key: r.id,
        payment_id: r.provider_payment_id,
        amount_money: {
          amount: r.entry_amount_cents + r.online_fee_cents,
          currency: r.currency.toUpperCase(),
        },
        reason: `[RM ${r.id}] ${r.reason}`.slice(0, 192),
      };
      if (payment.app_fee_money?.amount > 0) {
        // Explicitly keep application fees unless the secretary includes online
        // fees; Square otherwise refunds application fees proportionally.
        body.app_fee_money = {
          currency: r.currency.toUpperCase(),
          amount: r.online_fee_cents > 0
            ? Math.min(
              Number(payment.app_fee_money.amount),
              Math.floor(
                Number(payment.app_fee_money.amount) *
                  (r.entry_amount_cents + r.online_fee_cents) /
                  Number(payment.total_money.amount),
              ),
            )
            : 0,
        };
      }
      try {
        return read(
          (await squareRequest("/v2/refunds", token, {
            method: "POST",
            body: JSON.stringify(body),
          })).refund as Json,
        );
      } catch (error) {
        if (
          error instanceof SquareRequestError && error.status === 400 &&
          ["REFUND_AMOUNT_INVALID", "PAYMENT_NOT_REFUNDABLE", "REFUND_DECLINED"]
            .includes(error.code)
        ) {
          throw new RefundRejected(error.message);
        }
        throw error;
      }
    },
  };
}
