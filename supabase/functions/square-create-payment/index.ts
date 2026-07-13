import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  attachProviderHostedCheckout,
  claimPaymentAttemptClientKey,
  createPaymentQuoteAttempt,
  markPaymentAttemptTerminal,
  PaymentAttempt,
  supersedeProviderCheckout,
} from "../_shared/payment.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { sha256 } from "../_shared/token_crypto.ts";
import {
  SquareRequestError,
  squareEnvironment,
  squareRequest,
} from "../_shared/square.ts";
import { loadSquareAuthorization } from "../_shared/square_credentials.ts";

type RequestBody = { cart_id?: string; client_attempt_key?: string };
type ActiveAttempt = {
  id: string;
  provider: string;
  provider_session_id: string | null;
  provider_attempt_id: string | null;
  checkout_url: string | null;
  attempt_status: string;
  metadata: Record<string, unknown> | null;
};

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const backend = serviceClient();
  let attempt: PaymentAttempt | null = null;
  try {
    const { user } = await authenticatedUser(request);
    const body = await request.json() as RequestBody;
    const cartId = body.cart_id?.trim() ?? "";
    const clientAttemptKey = body.client_attempt_key?.trim() ?? "";
    if (!cartId || !clientAttemptKey || clientAttemptKey.length > 200) {
      return jsonResponse(
        { error: "cart_id and a valid client_attempt_key are required." },
        400,
      );
    }

    const { data: cart, error: cartError } = await backend.from("entry_carts")
      .select("show_id,user_id,status,payment_status,active_payment_session_id,selected_payment_timing,selected_payment_provider")
      .eq("id", cartId).maybeSingle();
    if (cartError || !cart || cart.user_id !== user.id) {
      throw new Error("You do not have access to this cart.");
    }
    if (cart.status !== "active" || cart.payment_status === "paid") {
      throw new Error("This cart is no longer available for checkout.");
    }

    const showId = String(cart.show_id);
    const { data: show, error: showError } = await backend.from("shows")
      .select("entry_close_at,payment_timing_mode")
      .eq("id", showId).maybeSingle();
    const { data: settings, error: settingsError } = await backend
      .from("show_payment_settings").select("square_enabled")
      .eq("show_id", showId).maybeSingle();
    if (showError || settingsError || !show ||
      !["online_only", "online_or_at_show"].includes(
        String(show.payment_timing_mode),
      ) || settings?.square_enabled !== true) {
      throw new Error("Square online payment is not enabled for this show.");
    }
    if (show.entry_close_at && Date.now() > Date.parse(String(show.entry_close_at))) {
      throw new Error("This show's entry deadline has passed.");
    }
    if (cart.selected_payment_timing && cart.selected_payment_timing !== "online") {
      throw new Error("This cart is not set to pay online.");
    }
    if (cart.selected_payment_provider && cart.selected_payment_provider !== "square") {
      throw new Error("This cart is assigned to a different payment provider.");
    }
    const authorization = await loadSquareAuthorization(backend, showId);
    const clientKeyHash = await sha256(clientAttemptKey);
    const active = cart.active_payment_session_id
      ? await loadActiveAttempt(String(cart.active_payment_session_id))
      : null;

    if (active?.provider === "square" && isUnresolved(active.attempt_status)) {
      const savedHash = String(active.metadata?.client_attempt_key_hash ?? "");
      if (savedHash === clientKeyHash && active.checkout_url) {
        return checkoutResponse(active.id, active.checkout_url);
      }
      if (savedHash && savedHash !== clientKeyHash) {
        await retireHostedCheckout(active, authorization.accessToken);
      }
    }

    attempt = await createPaymentQuoteAttempt(backend, {
      cartId,
      userId: user.id,
      provider: "square",
      platformFeeDefaultPercent: readNumberEnv(
        "RINGMASTER_PLATFORM_FEE_PERCENT",
        0.02,
      ),
      processingFeePercent: readRequiredNumber(
        "SQUARE_PROCESSING_FEE_PERCENT",
      ),
      processingFeeFixedCents: readRequiredInt(
        "SQUARE_PROCESSING_FEE_FIXED_CENTS",
      ),
    });
    const claim = await claimPaymentAttemptClientKey(backend, {
      paymentSessionId: attempt.payment_session_id,
      provider: "square",
      clientAttemptKeyHash: clientKeyHash,
    });
    if (claim.already_finalized === true) {
      throw new Error("This payment was already completed.");
    }
    if (attempt.checkout_url) {
      return checkoutResponse(attempt.payment_session_id, attempt.checkout_url);
    }

    const quote = attempt.quote;
    if (quote.show_id !== showId ||
      authorization.currency !== quote.currency.toLowerCase()) {
      throw new Error("The saved checkout currency does not match Square.");
    }

    const redirectUrl = buildRedirectUrl({
      cartId,
      paymentSessionId: attempt.payment_session_id,
    });
    const production = squareEnvironment === "production";
    const checkoutOptions: Record<string, unknown> = {
      redirect_url: redirectUrl,
      ask_for_shipping_address: false,
      allow_tipping: false,
      enable_coupon: false,
      enable_loyalty: false,
    };
    if (production) {
      checkoutOptions.app_fee_money = {
        amount: quote.platform_fee_cents,
        currency: quote.currency.toUpperCase(),
      };
    } else {
      console.info("Square Sandbox hosted checkout omits application fee", {
        paymentSessionId: attempt.payment_session_id,
        applicationFeeRequestedCents: quote.platform_fee_cents,
        limitation: "square_sandbox_payment_link",
      });
    }

    const squareData = await squareRequest(
      "/v2/online-checkout/payment-links",
      authorization.accessToken,
      {
        method: "POST",
        body: JSON.stringify({
          idempotency_key: await sha256(
            `square-link:${attempt.payment_session_id}`,
          ),
          description: `RingMaster Show entry payment for ${quote.show_name}`,
          order: {
            location_id: authorization.locationId,
            reference_id: attempt.payment_session_id,
            line_items: [{
              name: `${quote.show_name} Entries`,
              quantity: "1",
              item_type: "ITEM",
              base_price_money: {
                amount: quote.expected_amount_cents,
                currency: quote.currency.toUpperCase(),
              },
              note: `RingMaster payment ${attempt.payment_session_id}`,
            }],
          },
          checkout_options: checkoutOptions,
          payment_note: `RingMaster payment ${attempt.payment_session_id}`,
        }),
      },
    );
    const paymentLink = requireObject(squareData.payment_link, "Payment link");
    const paymentLinkId = requiredString(paymentLink.id, "Payment link ID");
    const orderId = requiredString(paymentLink.order_id, "Square order ID");
    const checkoutUrl = requiredString(paymentLink.url, "Checkout URL");

    await attachProviderHostedCheckout(backend, {
      paymentSessionId: attempt.payment_session_id,
      provider: "square",
      providerSessionId: paymentLinkId,
      providerAttemptId: orderId,
      checkoutUrl,
      providerMetadata: {
        checkout_type: "square_hosted_payment_link",
        square_payment_link_id: paymentLinkId,
        square_order_id: orderId,
        square_environment: production ? "production" : "sandbox",
        application_fee_requested_cents: quote.platform_fee_cents,
        application_fee_sent_to_provider: production,
        ...(!production
          ? {
            application_fee_test_limitation:
              "square_sandbox_payment_link",
          }
          : {}),
      },
    });

    return checkoutResponse(attempt.payment_session_id, checkoutUrl);
  } catch (error) {
    if (attempt && error instanceof SquareRequestError) {
      try {
        await markPaymentAttemptTerminal(backend, {
          paymentSessionId: attempt.payment_session_id,
          provider: "square",
          status: "failed",
          failureCode: error.code,
          failureMessage: error.message,
        });
      } catch (_) {
        // Preserve the original Square error without logging request details.
      }
    }
    return jsonResponse(
      { error: safeClientError(error) },
      errorMessage(error) === "Authentication required." ? 401 : 400,
    );
  }
});

async function loadActiveAttempt(id: string): Promise<ActiveAttempt | null> {
  const { data, error } = await serviceClient().from("show_payment_sessions")
    .select("id,provider,provider_session_id,provider_attempt_id,checkout_url,attempt_status,metadata")
    .eq("id", id).maybeSingle();
  if (error) throw new Error("Unable to load the active payment attempt.");
  return data as ActiveAttempt | null;
}

async function retireHostedCheckout(
  active: ActiveAttempt,
  accessToken: string,
): Promise<void> {
  let deactivated = false;
  if (active.provider_attempt_id) {
    const orderData = await squareRequest(
      `/v2/orders/${encodeURIComponent(active.provider_attempt_id)}`,
      accessToken,
    );
    const order = requireObject(orderData.order, "Square order");
    if (String(order.state ?? "") === "COMPLETED" ||
      (Array.isArray(order.tenders) && order.tenders.length > 0)) {
      throw new Error(
        "The previous Square checkout is already processing. Refresh its status before trying again.",
      );
    }
  }
  if (active.provider_session_id) {
    try {
      await squareRequest(
        `/v2/online-checkout/payment-links/${encodeURIComponent(active.provider_session_id)}`,
        accessToken,
        { method: "DELETE" },
      );
      deactivated = true;
    } catch (error) {
      if (!(error instanceof SquareRequestError && error.code === "NOT_FOUND")) {
        throw error;
      }
      deactivated = true;
    }
  }
  await supersedeProviderCheckout(serviceClient(), {
    paymentSessionId: active.id,
    provider: "square",
    linkDeactivated: deactivated,
  });
}

function buildRedirectUrl(args: {
  cartId: string;
  paymentSessionId: string;
}): string {
  const base = (Deno.env.get("RINGMASTER_APP_URL") ??
    Deno.env.get("APP_BASE_URL") ?? "").trim().replace(/\/$/, "");
  if (!base) throw new Error("Missing server configuration: RINGMASTER_APP_URL.");
  const query = new URLSearchParams({
    cart_id: args.cartId,
    payment_session_id: args.paymentSessionId,
  });
  return `${base}/#/square-payment-return?${query.toString()}`;
}

function checkoutResponse(paymentSessionId: string, checkoutUrl: string) {
  return jsonResponse({
    payment_session_id: paymentSessionId,
    checkout_url: checkoutUrl,
    provider: "square",
  });
}

function isUnresolved(status: string): boolean {
  return ["created", "pending", "processing"].includes(status);
}
function requireObject(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} is missing.`);
  }
  return value as Record<string, unknown>;
}
function requiredString(value: unknown, label: string): string {
  const text = String(value ?? "").trim();
  if (!text) throw new Error(`${label} is missing.`);
  return text;
}
function readRequiredNumber(name: string): number {
  const value = Number(Deno.env.get(name));
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`Missing or invalid server configuration: ${name}.`);
  }
  return value;
}
function readRequiredInt(name: string): number {
  return Math.round(readRequiredNumber(name));
}
function readNumberEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}
function safeClientError(error: unknown): string {
  if (error instanceof SquareRequestError) {
    return "Square could not create the secure checkout. Please try again.";
  }
  return errorMessage(error);
}
