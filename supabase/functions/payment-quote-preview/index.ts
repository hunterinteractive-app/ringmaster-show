import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  calculatePaymentFeeQuote,
  PaymentProvider,
} from "../_shared/payment.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";

type RequestBody = { cart_id?: string; provider?: string; timing?: string };

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const { user } = await authenticatedUser(request);
    const body = await request.json() as RequestBody;
    const cartId = body.cart_id?.trim() ?? "";
    const provider = body.provider?.trim().toLowerCase() as PaymentProvider;
    const timing = body.timing?.trim().toLowerCase() ?? "";
    if (!cartId || !["stripe", "square"].includes(provider)) {
      return jsonResponse({
        error: "A valid cart_id and provider are required.",
      }, 400);
    }
    if (timing !== "online") {
      return jsonResponse({
        error: "Online quote preview requires online timing.",
      }, 400);
    }

    const backend = serviceClient();
    const { data: cart, error: cartError } = await backend.from("entry_carts")
      .select("id,show_id,user_id,status,payment_status")
      .eq("id", cartId).maybeSingle();
    if (cartError || !cart || cart.user_id !== user.id) {
      throw new Error("You do not have access to this cart.");
    }
    if (cart.status !== "active" || cart.payment_status === "paid") {
      throw new Error("This cart is no longer available for checkout.");
    }

    const [
      { data: show, error: showError },
      { data: settings, error: settingsError },
    ] = await Promise.all([
      backend.from("shows").select(
        "id,payment_timing_mode,online_payment_fee_mode,online_payment_fee_label,online_payment_fee_description,platform_fee_percent",
      ).eq("id", cart.show_id).maybeSingle(),
      backend.from("show_payment_settings").select(
        "stripe_enabled,square_enabled",
      )
        .eq("show_id", cart.show_id).maybeSingle(),
    ]);
    if (showError || settingsError || !show) {
      throw new Error("Unable to load payment settings.");
    }
    if (
      !["online_only", "online_or_at_show"].includes(
        String(show.payment_timing_mode),
      )
    ) {
      throw new Error("This show does not allow online payment.");
    }
    if (provider === "stripe" && settings?.stripe_enabled !== true) {
      throw new Error("Stripe is not enabled for this show.");
    }
    if (provider === "square" && settings?.square_enabled !== true) {
      throw new Error("Square is not enabled for this show.");
    }

    const { data: balances, error: balanceError } = await backend.rpc(
      "calculate_entry_cart_balance",
      { p_cart_id: cartId },
    );
    if (balanceError) throw new Error(balanceError.message);
    const rows = Array.isArray(balances) ? balances : [];
    const currencies = new Set(
      rows.map((row) => String(row.currency ?? "").toLowerCase()),
    );
    const baseTotalCents = rows.reduce(
      (sum, row) => sum + Number(row.balance_due_cents ?? 0),
      0,
    );
    if (currencies.size !== 1 || baseTotalCents <= 0) {
      throw new Error("Unable to calculate a valid cart total.");
    }

    const platformDefault = readNumber("RINGMASTER_PLATFORM_FEE_PERCENT", 0.02);
    const processingPercent = provider === "square"
      ? readRequiredNumber("SQUARE_PROCESSING_FEE_PERCENT")
      : readNumber("STRIPE_PROCESSING_FEE_PERCENT", 0.029);
    const processingFixed = provider === "square"
      ? readRequiredNumber("SQUARE_PROCESSING_FEE_FIXED_CENTS")
      : readNumber("STRIPE_PROCESSING_FEE_FIXED_CENTS", 30);
    const quote = calculatePaymentFeeQuote({
      baseTotalCents,
      passFeeToExhibitor: show.online_payment_fee_mode === "pass_to_exhibitor",
      platformFeePercent: Number(show.platform_fee_percent ?? platformDefault),
      processingFeePercent: processingPercent,
      processingFeeFixedCents: processingFixed,
    });

    return jsonResponse({
      provider,
      timing,
      currency: [...currencies][0],
      fee_mode: String(show.online_payment_fee_mode ?? "club_absorbs"),
      fee_label: String(show.online_payment_fee_label ?? "Online Payment Fee"),
      fee_description: String(show.online_payment_fee_description ?? ""),
      base_total_cents: quote.baseTotalCents,
      online_processing_fee_cents: quote.onlineFeeCents,
      amount_due_cents: quote.expectedAmountCents,
      platform_fee_cents: quote.platformFeeCents,
      calculation_version: 1,
    });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});

function readNumber(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name) ?? fallback);
  if (!Number.isFinite(value) || value < 0) throw new Error(`Invalid ${name}.`);
  return value;
}

function readRequiredNumber(name: string): number {
  const raw = Deno.env.get(name)?.trim();
  if (!raw) throw new Error(`Missing ${name}.`);
  return readNumber(name, 0);
}
