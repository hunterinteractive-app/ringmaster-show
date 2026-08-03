import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  attachProviderSession,
  createPaymentQuoteAttempt,
  markPaymentAttemptTerminal,
} from "../_shared/payment.ts";
import { serviceClient } from "../_shared/supabase.ts";

type Body = { session_token?: string; return_token?: string };

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const backend = serviceClient();
  let paymentSessionId: string | null = null;
  try {
    const body = await request.json() as Body;
    const sessionToken = body.session_token?.trim() ?? "";
    const returnToken = body.return_token?.trim() ?? "";
    if (!sessionToken) return jsonResponse({ error: "Check-in session is required." }, 400);

    const { data: context, error: contextError } = await backend.rpc(
      "get_exhibitor_checkin_checkout_context",
      { p_session_token: sessionToken },
    );
    if (contextError || !context) throw new Error("This payment is no longer available.");
    const cartId = String(context.cart_id ?? "");
    const userId = String(context.user_id ?? "");
    if (!cartId || !userId) throw new Error("This payment is unavailable.");

    const attempt = await createPaymentQuoteAttempt(backend, {
      cartId,
      userId,
      provider: "stripe",
      platformFeeDefaultPercent: numberEnv("RINGMASTER_PLATFORM_FEE_PERCENT", 0.02),
      processingFeePercent: numberEnv("STRIPE_PROCESSING_FEE_PERCENT", 0.029),
      processingFeeFixedCents: intEnv("STRIPE_PROCESSING_FEE_FIXED_CENTS", 30),
    });
    paymentSessionId = attempt.payment_session_id;
    if (attempt.checkout_url && !expired(attempt.expires_at)) {
      return jsonResponse({ checkout_url: attempt.checkout_url }, 200);
    }

    const quote = attempt.quote;
    const { data: account } = await backend.from("show_payment_account_links")
      .select("stripe_account_id,charges_enabled,account_status")
      .eq("show_id", quote.show_id).eq("provider", "stripe").maybeSingle();
    const accountId = String(account?.stripe_account_id ?? "").trim();
    if (!accountId || account?.charges_enabled !== true || account?.account_status !== "ready") {
      throw new Error("Online payment is not ready for this show.");
    }

    const appBase = "https://checkin.ringmasterone.com";
    const form = new URLSearchParams();
    form.set("mode", "payment");
    const returnUrl = `${appBase}/#/checkin${returnToken ? `?token=${encodeURIComponent(returnToken)}` : ""}`;
    form.set("success_url", returnUrl);
    form.set("cancel_url", returnUrl);
    for (const [key, value] of Object.entries({
      cart_id: quote.cart_id,
      show_id: quote.show_id,
      exhibitor_user_id: userId,
      payment_session_id: attempt.payment_session_id,
      quote_hash: attempt.quote_hash,
      provider: "stripe",
      source: "exhibitor_checkin",
    })) {
      form.set(`metadata[${key}]`, value);
      form.set(`payment_intent_data[metadata][${key}]`, value);
    }
    form.set("payment_intent_data[application_fee_amount]", String(quote.platform_fee_cents));
    lineItem(form, 0, quote.currency, `${quote.show_name} Entries`, quote.show_balance_total_cents);
    if (quote.online_fee_cents > 0) lineItem(form, 1, quote.currency, quote.online_payment_fee_label, quote.online_fee_cents);

    const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requiredEnv("STRIPE_SECRET_KEY")}`,
        "Stripe-Account": accountId,
        "Content-Type": "application/x-www-form-urlencoded",
        "Idempotency-Key": attempt.idempotency_key,
      },
      body: form,
    });
    const stripe = await response.json() as Record<string, unknown>;
    if (!response.ok || typeof stripe.id !== "string" || typeof stripe.url !== "string") {
      throw new Error("Stripe could not create the secure checkout.");
    }
    const expiresAt = typeof stripe.expires_at === "number"
      ? new Date(stripe.expires_at * 1000).toISOString() : null;
    await attachProviderSession(backend, {
      paymentSessionId: attempt.payment_session_id,
      provider: "stripe",
      providerSessionId: stripe.id,
      checkoutUrl: stripe.url,
      expiresAt,
    });
    return jsonResponse({ checkout_url: stripe.url }, 200);
  } catch (error) {
    if (paymentSessionId) {
      await markPaymentAttemptTerminal(backend, {
        paymentSessionId,
        provider: "stripe",
        status: "failed",
        failureCode: "checkin_checkout_failed",
        failureMessage: errorMessage(error),
      }).catch(() => undefined);
    }
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});

function lineItem(form: URLSearchParams, index: number, currency: string, name: string, amount: number) {
  const prefix = `line_items[${index}]`;
  form.set(`${prefix}[price_data][currency]`, currency);
  form.set(`${prefix}[price_data][product_data][name]`, name);
  form.set(`${prefix}[price_data][unit_amount]`, String(amount));
  form.set(`${prefix}[quantity]`, "1");
}
function requiredEnv(name: string): string { const value = Deno.env.get(name)?.trim(); if (!value) throw new Error("Payment service is not configured."); return value; }
function numberEnv(name: string, fallback: number): number { const value = Number(Deno.env.get(name)); return Number.isFinite(value) && value >= 0 ? value : fallback; }
function intEnv(name: string, fallback: number): number { return Math.round(numberEnv(name, fallback)); }
function expired(value: string | null | undefined): boolean { return !!value && Date.parse(value) <= Date.now(); }
