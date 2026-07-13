// supabase/functions/stripe-connect-create-login-link/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type CreateLoginLinkBody = {
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

    const body = (await req.json()) as CreateLoginLinkBody;
    const showId = body.show_id?.trim();

    if (!showId) {
      return json({ error: "show_id is required." }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      global: {
        headers: { Authorization: authHeader },
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
      .select("id, created_by, club_id")
      .eq("id", showId)
      .maybeSingle();

    if (showError || !show) {
      return json({ error: "Show not found." }, 404);
    }

    const showOwnerId = (show as any).created_by?.toString();
    if (!showOwnerId || showOwnerId !== user.id) {
      return json({ error: "You do not have access to this show." }, 403);
    }

    const { data: accountRow, error: accountError } = await supabase
      .from("show_payment_account_links")
      .select("*")
      .eq("show_id", showId)
      .eq("provider", "stripe")
      .maybeSingle();

    if (accountError) {
      return json(
        {
          error: "Failed to load Stripe account for this show.",
          details: accountError.message,
        },
        500,
      );
    }

    if (!accountRow) {
      return json({ error: "No Stripe account found for this show." }, 400);
    }

    const stripeAccountId = (accountRow as any).stripe_account_id?.toString();
    if (!stripeAccountId) {
      return json({ error: "Stripe account ID missing." }, 400);
    }

    const stripeRes = await fetch(
      `https://api.stripe.com/v1/accounts/${stripeAccountId}/login_links`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
      },
    );

    const stripeJson = await stripeRes.json();

    if (!stripeRes.ok) {
      return json(
        {
          error: "Stripe login link creation failed.",
          details: stripeJson,
        },
        400,
      );
    }

    return json({
      ok: true,
      url: stripeJson.url,
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