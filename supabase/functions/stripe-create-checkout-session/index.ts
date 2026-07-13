import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  attachProviderSession,
  createPaymentQuoteAttempt,
  markPaymentAttemptTerminal,
  PaymentAttempt,
} from "../_shared/payment.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";

type CheckoutBody = { cart_id?: string };

serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  let attempt: PaymentAttempt | null = null;
  const backend = serviceClient();

  try {
    const stripeSecretKey = requiredEnv("STRIPE_SECRET_KEY");
    const appBaseUrl = requiredEnv("APP_BASE_URL");
    const { user } = await authenticatedUser(request);
    const body = (await request.json()) as CheckoutBody;
    const cartId = body.cart_id?.trim();
    if (!cartId) return jsonResponse({ error: "cart_id is required." }, 400);

    attempt = await createPaymentQuoteAttempt(backend, {
      cartId,
      userId: user.id,
      provider: "stripe",
      platformFeeDefaultPercent: readNumberEnv(
        "RINGMASTER_PLATFORM_FEE_PERCENT",
        0.02,
      ),
      processingFeePercent: readNumberEnv(
        "STRIPE_PROCESSING_FEE_PERCENT",
        0.029,
      ),
      processingFeeFixedCents: readIntEnv(
        "STRIPE_PROCESSING_FEE_FIXED_CENTS",
        30,
      ),
    });

    if (attempt.checkout_url && !isExpired(attempt.expires_at)) {
      return checkoutResponse(attempt);
    }

    const quote = attempt.quote;
    const { data: account, error: accountError } = await backend
      .from("show_payment_account_links")
      .select("stripe_account_id,charges_enabled,account_status")
      .eq("show_id", quote.show_id)
      .eq("provider", "stripe")
      .maybeSingle();
    if (accountError) throw new Error("Unable to load the Stripe account.");

    const connectedAccountId = account?.stripe_account_id?.toString().trim();
    if (
      !connectedAccountId ||
      account?.charges_enabled !== true ||
      account?.account_status !== "ready"
    ) {
      throw new Error(
        "This show's Stripe account is not yet ready to accept charges.",
      );
    }

    const form = buildStripeSessionForm({
      attempt,
      appBaseUrl,
      userId: user.id,
    });
    const stripeResponse = await fetch(
      "https://api.stripe.com/v1/checkout/sessions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
          "Stripe-Account": connectedAccountId,
          "Content-Type": "application/x-www-form-urlencoded",
          "Idempotency-Key": attempt.idempotency_key,
        },
        body: form.toString(),
      },
    );
    const stripeJson = await stripeResponse.json() as Record<string, unknown>;

    if (!stripeResponse.ok) {
      const stripeError = stripeJson.error as
        | Record<string, unknown>
        | undefined;
      const code = stringValue(stripeError?.code) ?? "stripe_session_failed";
      const message = stringValue(stripeError?.message) ??
        "Stripe Checkout Session creation failed.";
      await markPaymentAttemptTerminal(backend, {
        paymentSessionId: attempt.payment_session_id,
        provider: "stripe",
        status: "failed",
        failureCode: code,
        failureMessage: message,
      });
      return jsonResponse({
        error: "Stripe Checkout Session creation failed.",
        details: message,
      }, 400);
    }

    const sessionId = stringValue(stripeJson.id);
    const checkoutUrl = stringValue(stripeJson.url);
    if (!sessionId || !checkoutUrl) {
      throw new Error("Stripe returned an incomplete Checkout Session.");
    }
    const expiresAt = unixSecondsToIso(stripeJson.expires_at);

    await attachProviderSession(backend, {
      paymentSessionId: attempt.payment_session_id,
      provider: "stripe",
      providerSessionId: sessionId,
      checkoutUrl,
      expiresAt,
    });

    attempt = {
      ...attempt,
      provider_session_id: sessionId,
      checkout_url: checkoutUrl,
      expires_at: expiresAt,
    };
    return checkoutResponse(attempt);
  } catch (error) {
    return jsonResponse(
      {
        error: "Unable to start online payment.",
        details: errorMessage(error),
      },
      errorMessage(error) === "Authentication required." ? 401 : 400,
    );
  }
});

function buildStripeSessionForm(args: {
  attempt: PaymentAttempt;
  appBaseUrl: string;
  userId: string;
}): URLSearchParams {
  const { attempt, appBaseUrl, userId } = args;
  const quote = attempt.quote;
  const form = new URLSearchParams();
  form.set("mode", "payment");
  form.set(
    "success_url",
    `${appBaseUrl}/#/entries?show_id=${quote.show_id}&stripe=success&session_id={CHECKOUT_SESSION_ID}`,
  );
  form.set(
    "cancel_url",
    `${appBaseUrl}/#/cart?cart_id=${quote.cart_id}&show_id=${quote.show_id}&show_name=${
      encodeURIComponent(quote.show_name)
    }&stripe=cancel`,
  );
  form.set("submit_type", "pay");

  const metadata: Record<string, string> = {
    cart_id: quote.cart_id,
    show_id: quote.show_id,
    exhibitor_user_id: userId,
    payment_session_id: attempt.payment_session_id,
    quote_hash: attempt.quote_hash,
    provider: "stripe",
    platform: "RingMaster Show",
  };
  for (const [key, value] of Object.entries(metadata)) {
    form.set(`metadata[${key}]`, value);
    form.set(`payment_intent_data[metadata][${key}]`, value);
  }

  form.set(
    "payment_intent_data[application_fee_amount]",
    String(quote.platform_fee_cents),
  );
  setLineItem(form, 0, {
    currency: quote.currency,
    name: `${quote.show_name} Entries`,
    description: "RingMaster Show entry fees",
    amountCents: quote.show_balance_total_cents,
  });
  if (quote.online_fee_cents > 0) {
    setLineItem(form, 1, {
      currency: quote.currency,
      name: quote.online_payment_fee_label,
      description: quote.online_payment_fee_description,
      amountCents: quote.online_fee_cents,
    });
  }
  return form;
}

function setLineItem(
  form: URLSearchParams,
  index: number,
  item: {
    currency: string;
    name: string;
    description: string;
    amountCents: number;
  },
): void {
  const prefix = `line_items[${index}]`;
  form.set(`${prefix}[price_data][currency]`, item.currency);
  form.set(`${prefix}[price_data][product_data][name]`, item.name);
  form.set(
    `${prefix}[price_data][product_data][description]`,
    item.description,
  );
  form.set(`${prefix}[price_data][unit_amount]`, String(item.amountCents));
  form.set(`${prefix}[quantity]`, "1");
}

function checkoutResponse(attempt: PaymentAttempt): Response {
  const quote = attempt.quote;
  return jsonResponse({
    ok: true,
    charge_type: "direct",
    payment_mode: "per_exhibitor_balance_rows",
    payment_session_id: attempt.payment_session_id,
    checkout_session_id: attempt.provider_session_id,
    checkout_url: attempt.checkout_url,
    quote_hash: attempt.quote_hash,
    amount_total: centsToDollars(quote.expected_amount_cents),
    amount_total_cents: quote.expected_amount_cents,
    show_balance_total: centsToDollars(quote.show_balance_total_cents),
    show_balance_total_cents: quote.show_balance_total_cents,
    online_payment_fee_mode: quote.online_payment_fee_mode,
    online_payment_fee_amount: centsToDollars(quote.online_fee_cents),
    online_payment_fee_cents: quote.online_fee_cents,
    platform_fee_amount: centsToDollars(quote.platform_fee_cents),
    platform_fee_cents: quote.platform_fee_cents,
    fee_breakdown: {
      show_balance_total_cents: quote.show_balance_total_cents,
      online_payment_fee_cents: quote.online_fee_cents,
      total_cents: quote.expected_amount_cents,
    },
    balances: quote.balances,
  }, 200);
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}.`);
  return value;
}

function readNumberEnv(name: string, fallback: number): number {
  const parsed = Number(Deno.env.get(name));
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function readIntEnv(name: string, fallback: number): number {
  return Math.round(readNumberEnv(name, fallback));
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function unixSecondsToIso(value: unknown): string | null {
  const seconds = Number(value);
  return Number.isFinite(seconds) && seconds > 0
    ? new Date(seconds * 1000).toISOString()
    : null;
}

function isExpired(value: string | null | undefined): boolean {
  if (!value) return false;
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) && timestamp <= Date.now();
}

function centsToDollars(cents: number): number {
  return Number((cents / 100).toFixed(2));
}
