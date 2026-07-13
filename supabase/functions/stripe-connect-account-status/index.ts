// supabase/functions/stripe-connect-account-status/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type StatusBody = {
  show_id: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!stripeSecretKey || !supabaseUrl || !serviceRoleKey) {
      return json({ error: "Missing required environment variables." }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "Missing Authorization header." }, 401);
    }

    const body = (await req.json()) as StatusBody;
    const showId = body.show_id?.trim();

    if (!showId) {
      return json({ error: "show_id is required." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return json({ error: "Unauthorized." }, 401);
    }

    const { data: show, error: showError } = await supabase
      .from("shows")
      .select("id, created_by, club_id, name, club_name")
      .eq("id", showId)
      .maybeSingle();

    if (showError) {
      return json(
        {
          error: "Failed to load show.",
          details: showError.message,
        },
        500,
      );
    }

    if (!show) {
      return json({ error: "Show not found." }, 404);
    }

    const createdBy = (show as any).created_by?.toString();
    const clubId = (show as any).club_id?.toString();

    let isManager = false;

    if (createdBy === user.id) {
      isManager = true;
    }

    if (!isManager && clubId) {
      const { data: membership, error: membershipError } = await supabase
        .from("club_members")
        .select("id")
        .eq("club_id", clubId)
        .eq("user_id", user.id)
        .eq("is_active", true)
        .maybeSingle();

      if (membershipError) {
        return json(
          {
            error: "Failed to verify club membership.",
            details: membershipError.message,
          },
          500,
        );
      }

      if (membership) {
        isManager = true;
      }
    }

    const { data: accountRows, error: accountError } = await supabase
      .from("show_payment_account_links")
      .select("*")
      .eq("show_id", showId)
      .eq("provider", "stripe")
      .order("updated_at", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1);

    if (accountError) {
      return json(
        {
          error: "Failed to load Stripe account.",
          details: accountError.message,
        },
        500,
      );
    }

    const accountRow =
      accountRows && accountRows.length > 0 ? accountRows[0] : null;

    if (!accountRow) {
      return json({
        ok: true,
        status: "not_connected",
        charges_enabled: false,
        payouts_enabled: false,
        details_submitted: false,
        requirements: {
          currently_due: [],
          past_due: [],
          pending_verification: [],
        },
        show_payment_account: null,
      });
    }

    const stripeAccountId = (accountRow as any).stripe_account_id
      ?.toString()
      .trim();

    if (!stripeAccountId) {
      return json({
        ok: true,
        status: "not_connected",
        charges_enabled: false,
        payouts_enabled: false,
        details_submitted: false,
        requirements: {
          currently_due: [],
          past_due: [],
          pending_verification: [],
        },
        show_payment_account: accountRow,
      });
    }

    const stripeRes = await fetch(
      `https://api.stripe.com/v1/accounts/${stripeAccountId}`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
        },
      },
    );

    const stripeJson = await stripeRes.json();

    if (!stripeRes.ok) {
      return json(
        {
          error: "Failed to load Stripe account from Stripe.",
          details: stripeJson,
        },
        400,
      );
    }

    const chargesEnabled = stripeJson.charges_enabled === true;
    const payoutsEnabled = stripeJson.payouts_enabled === true;
    const detailsSubmitted = stripeJson.details_submitted === true;

    let status = "pending_onboarding";

    const cardPaymentsActive =
      stripeJson.capabilities?.card_payments === "active";

    const hasDisabledReason =
      !!stripeJson.requirements?.disabled_reason;

    if (
     chargesEnabled &&
     payoutsEnabled &&
     detailsSubmitted &&
     cardPaymentsActive &&
     !hasDisabledReason
    ) {
      status = "ready";
    } else if (
      (stripeJson.requirements?.currently_due?.length ?? 0) > 0 ||
      (stripeJson.requirements?.past_due?.length ?? 0) > 0
    ) {
      status = "restricted";
    }

    const { error: updateError } = await supabase
      .from("show_payment_account_links")
      .update({
        charges_enabled: chargesEnabled,
        payouts_enabled: payoutsEnabled,
        details_submitted: detailsSubmitted,
        account_status: status,
        metadata: stripeJson,
        updated_at: new Date().toISOString(),
      })
      .eq("id", accountRow.id);

    if (updateError) {
      console.error("Failed updating show_payment_account_links", updateError);
    }

    return json({
      ok: true,
      status,
      charges_enabled: chargesEnabled,
      payouts_enabled: payoutsEnabled,
      details_submitted: detailsSubmitted,

      card_payments_active: cardPaymentsActive,
      disabled_reason: stripeJson.requirements?.disabled_reason ?? null,
      
      requirements: {
        currently_due: stripeJson.requirements?.currently_due ?? [],
        past_due: stripeJson.requirements?.past_due ?? [],
        pending_verification:
          stripeJson.requirements?.pending_verification ?? [],
      },
      
      show_payment_account: {
        ...accountRow,
        charges_enabled: chargesEnabled,
        payouts_enabled: payoutsEnabled,
        details_submitted: detailsSubmitted,
        account_status: status,
      },
    });
  } catch (error) {
    return json(
      {
        error: "Unexpected server error.",
        details: error instanceof Error ? error.message : String(error),
      },
      500,
    );
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}