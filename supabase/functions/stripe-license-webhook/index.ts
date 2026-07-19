/// <reference lib="deno.ns" />

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "npm:stripe@14.25.0";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import {
  isCompletedLicenseCheckoutEvent,
  isCompletedSuccessfulLicensePurchase,
  normalizeSecretaryEmail,
  sendLicensePurchaseEmail,
} from "../_shared/license_purchase_email.ts";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2023-10-16" as Stripe.LatestApiVersion,
});

const PAYMENT_LINK_SINGLE_SHOW_ID = "plink_1TJgcCLAhl5IBJ5kAjGbfWQ1";
const PAYMENT_LINK_FOUR_SHOWS_ID = "plink_1TJgh0LAhl5IBJ5kqxW3kFyG";
const PAYMENT_LINK_UNLIMITED_ID = "plink_1TJghzLAhl5IBJ5kgZHyciA2";
const PAYMENT_LINK_MULTI_CLUB_ID = "plink_1TFHLcLAhl5IBJ5kj7bzFfuh";

type AdminClient = ReturnType<typeof createClient<any>>;

type LicensePlanResult = {
  addShowDays: number;
  setUnlimitedAccess: boolean;
  setCanChangeHostClub: boolean;
  unlimitedExpiresAt: string | null;
  matchedPlan: string;
};

function resolvePlanFromPaymentLink(
  paymentLinkId: string | null,
): LicensePlanResult | null {
  let addShowDays = 0;
  let setUnlimitedAccess = false;
  let setCanChangeHostClub = false;
  let unlimitedExpiresAt: string | null = null;
  let matchedPlan = "";

  if (paymentLinkId === PAYMENT_LINK_SINGLE_SHOW_ID) {
    addShowDays = 1;
    matchedPlan = "single_show";
  } else if (paymentLinkId === PAYMENT_LINK_FOUR_SHOWS_ID) {
    addShowDays = 4;
    matchedPlan = "four_shows";
  } else if (paymentLinkId === PAYMENT_LINK_UNLIMITED_ID) {
    setUnlimitedAccess = true;
    matchedPlan = "unlimited";

    const expires = new Date();
    expires.setFullYear(expires.getFullYear() + 1);
    unlimitedExpiresAt = expires.toISOString();
  } else if (paymentLinkId === PAYMENT_LINK_MULTI_CLUB_ID) {
    setCanChangeHostClub = true;
    matchedPlan = "multi_club";
  } else {
    return null;
  }

  return {
    addShowDays,
    setUnlimitedAccess,
    setCanChangeHostClub,
    unlimitedExpiresAt,
    matchedPlan,
  };
}

function getCustomFieldValue(
  customFields: Stripe.Checkout.Session.CustomField[] | null | undefined,
  possibleKeys: string[],
  possibleLabels: string[],
): string | null {
  const normalizedKeys = possibleKeys.map((v) => v.trim().toLowerCase());
  const normalizedLabels = possibleLabels.map((v) => v.trim().toLowerCase());

  const field = (customFields ?? []).find((item) => {
    const key = (item?.key ?? "").toString().trim().toLowerCase();
    const label = (item?.label?.custom ?? "").toString().trim().toLowerCase();

    return normalizedKeys.includes(key) || normalizedLabels.includes(label);
  });

  return field?.text?.value?.trim() || null;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const signature = req.headers.get("stripe-signature");
  if (!signature) {
    console.error("Missing stripe-signature header");
    return new Response("Missing stripe-signature header", { status: 400 });
  }

  const webhookSecretRaw = Deno.env.get("STRIPE_LICENSE_WEBHOOK_SECRET");
  if (!webhookSecretRaw) {
    console.error("Missing STRIPE_LICENSE_WEBHOOK_SECRET");
    return new Response("Missing STRIPE_LICENSE_WEBHOOK_SECRET", {
      status: 500,
    });
  }

  const webhookSecret = webhookSecretRaw.trim();

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Missing Supabase env vars");
    return new Response("Missing Supabase env vars", { status: 500 });
  }

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      webhookSecret,
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("Webhook signature verification failed:", message);
    return new Response(`Webhook Error: ${message}`, { status: 400 });
  }

  console.log("Webhook received:", event.type);

  if (!isCompletedLicenseCheckoutEvent(event.type)) {
    return new Response("ok", { status: 200 });
  }

  const session = event.data.object as Stripe.Checkout.Session;
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const fullSession = await stripe.checkout.sessions.retrieve(session.id, {
    expand: ["line_items.data.price.product", "payment_link"],
  });

  if (
    !isCompletedSuccessfulLicensePurchase(
      fullSession.status,
      fullSession.payment_status,
    )
  ) {
    console.log("Ignoring incomplete or unpaid license checkout", {
      eventId: event.id,
      sessionId: fullSession.id,
      status: fullSession.status,
      paymentStatus: fullSession.payment_status,
    });
    return new Response("Ignored incomplete purchase", { status: 200 });
  }

  const paymentLinkId = typeof fullSession.payment_link === "string"
    ? fullSession.payment_link
    : fullSession.payment_link?.id ?? null;

  const paymentLinkUrl = typeof fullSession.payment_link === "string"
    ? null
    : fullSession.payment_link?.url ?? null;

  const plan = resolvePlanFromPaymentLink(paymentLinkId);

  if (!plan) {
    console.error("Unknown payment link.");
    console.error("session.id:", session.id);
    console.error("paymentLinkId:", paymentLinkId);
    console.error("paymentLinkUrl:", paymentLinkUrl);
    return new Response(`Unknown payment link: ${paymentLinkId ?? "null"}`, {
      status: 400,
    });
  }

  const customFields = fullSession.custom_fields ?? [];

  const secretaryEmail = normalizeSecretaryEmail(
    getCustomFieldValue(
      customFields,
      ["showsecretaryemail", "show_secretary_email"],
      ["Show Secretary Email"],
    ),
  ) ||
    normalizeSecretaryEmail(fullSession.customer_details?.email) ||
    normalizeSecretaryEmail(fullSession.customer_email);

  const secretaryName = getCustomFieldValue(
    customFields,
    ["showsecretaryname", "show_secretary_name"],
    ["Show Secretary Name"],
  ) || null;

  if (!secretaryEmail) {
    console.error("No secretary email found in session:", session.id);
    return new Response("No secretary email found", { status: 400 });
  }

  const {
    data: existingProcessedSession,
    error: existingProcessedSessionError,
  } = await supabase
    .from("processed_stripe_sessions")
    .select("stripe_session_id,secretary_email,matched_user_id,matched_plan")
    .eq("stripe_session_id", session.id)
    .maybeSingle();

  if (existingProcessedSessionError) {
    console.error(
      "Error checking processed_stripe_sessions for duplicate session:",
      existingProcessedSessionError,
    );
    return new Response("Failed duplicate check", { status: 500 });
  }

  if (existingProcessedSession) {
    await deliverPurchaseEmail({
      supabase,
      eventId: event.id,
      sessionId: session.id,
      secretaryEmail,
      secretaryName,
      matchedUserId: existingProcessedSession.matched_user_id,
      matchedPlan: existingProcessedSession.matched_plan ?? plan.matchedPlan,
      completedAt: new Date(event.created * 1000).toISOString(),
    });
    console.log("Session already processed:", session.id);
    return new Response("Already processed", { status: 200 });
  }

  console.log("Session ID:", session.id);
  console.log("Payment link ID:", paymentLinkId);
  console.log("Payment link URL:", paymentLinkUrl);
  console.log("Matched plan:", plan.matchedPlan);
  console.log("Resolved secretary email:", secretaryEmail);
  console.log("Resolved secretary name:", secretaryName);
  console.log("Custom fields:", JSON.stringify(customFields));

  const { data: usersResult, error: usersError } = await supabase.auth.admin
    .listUsers();

  if (usersError) {
    console.error("Error listing users:", usersError);
    return new Response("Error listing users", { status: 500 });
  }

  const matchedUser = (usersResult.users ?? []).find(
    (u) =>
      (u.email ?? "").trim().toLowerCase() === secretaryEmail.toLowerCase(),
  );

  if (!matchedUser) {
    const { error: insertPendingError } = await supabase
      .from("pending_licenses")
      .insert({
        email: secretaryEmail,
        secretary_name: secretaryName,
        stripe_session_id: session.id,
        purchased_show_days: plan.addShowDays,
        unlimited_access: plan.setUnlimitedAccess,
        unlimited_expires_at: plan.unlimitedExpiresAt,
        can_change_host_club: plan.setCanChangeHostClub,
        claimed_at: null,
      });

    if (insertPendingError) {
      console.error("Failed to insert pending license:", insertPendingError);
      return new Response("Failed to store pending license", { status: 500 });
    }

    const { error: processedInsertError } = await supabase
      .from("processed_stripe_sessions")
      .insert({
        stripe_session_id: session.id,
        secretary_email: secretaryEmail,
        matched_user_id: null,
        matched_plan: plan.matchedPlan,
      });

    if (processedInsertError) {
      console.error(
        "Failed to insert processed session after pending license insert:",
        processedInsertError,
      );
      return new Response("Failed to record processed session", {
        status: 500,
      });
    }

    await deliverPurchaseEmail({
      supabase,
      eventId: event.id,
      sessionId: session.id,
      secretaryEmail,
      secretaryName,
      matchedUserId: null,
      matchedPlan: plan.matchedPlan,
      completedAt: new Date(event.created * 1000).toISOString(),
    });

    console.log(
      "No matching user found. Stored pending license for:",
      secretaryEmail,
    );
    return new Response("Stored for later", { status: 200 });
  }

  const userId = matchedUser.id;

  const { data: existingRow, error: existingError } = await supabase
    .from("account_license_balances")
    .select(
      "user_id,purchased_show_days,consumed_show_days,unlimited_access,unlimited_active,unlimited_expires_at,can_change_host_club",
    )
    .eq("user_id", userId)
    .maybeSingle();

  if (existingError) {
    console.error(
      "Failed to read existing account_license_balances row:",
      existingError,
    );
    return new Response("Failed to read current license balance", {
      status: 500,
    });
  }

  const existingPurchasedShowDays = Number(
    existingRow?.purchased_show_days ?? 0,
  );

  const payload: Record<string, unknown> = {
    user_id: userId,
    purchased_show_days: existingPurchasedShowDays + plan.addShowDays,
    updated_at: new Date().toISOString(),
    unlimited_access: existingRow?.unlimited_access ?? false,
    unlimited_active: existingRow?.unlimited_active ?? false,
    unlimited_expires_at: existingRow?.unlimited_expires_at ?? null,
    can_change_host_club: existingRow?.can_change_host_club ?? false,
    secretary_name: secretaryName,
    secretary_email: secretaryEmail,
  };

  if (plan.setUnlimitedAccess) {
    payload.unlimited_access = true;
    payload.unlimited_active = true;
    payload.unlimited_expires_at = plan.unlimitedExpiresAt;
  }

  if (plan.setCanChangeHostClub) {
    payload.can_change_host_club = true;
  }

  const { error: upsertError } = await supabase
    .from("account_license_balances")
    .upsert(payload, { onConflict: "user_id" });

  if (upsertError) {
    console.error(
      "Failed to upsert account_license_balances:",
      upsertError,
    );
    return new Response("Failed to update license balance", { status: 500 });
  }

  const { error: processedInsertError } = await supabase
    .from("processed_stripe_sessions")
    .insert({
      stripe_session_id: session.id,
      secretary_email: secretaryEmail,
      matched_user_id: userId,
      matched_plan: plan.matchedPlan,
    });

  if (processedInsertError) {
    console.error(
      "Failed to insert processed session after account update:",
      processedInsertError,
    );
    return new Response("Failed to record processed session", {
      status: 500,
    });
  }

  await deliverPurchaseEmail({
    supabase,
    eventId: event.id,
    sessionId: session.id,
    secretaryEmail,
    secretaryName,
    matchedUserId: userId,
    matchedPlan: plan.matchedPlan,
    completedAt: new Date(event.created * 1000).toISOString(),
  });

  console.log("License applied to:", secretaryEmail);
  console.log("User ID:", userId);
  console.log("Final payload:", JSON.stringify(payload));

  return new Response("ok", { status: 200 });
});

async function deliverPurchaseEmail(args: {
  supabase: AdminClient;
  eventId: string;
  sessionId: string;
  secretaryEmail: string;
  secretaryName: string | null;
  matchedUserId: string | null;
  matchedPlan: string;
  completedAt: string;
}): Promise<void> {
  const { data, error } = await args.supabase.rpc(
    "claim_license_purchase_email",
    {
      p_provider: "stripe",
      p_provider_event_id: args.eventId,
      p_provider_transaction_id: args.sessionId,
      p_secretary_email: args.secretaryEmail,
      p_matched_user_id: args.matchedUserId,
      p_matched_plan: args.matchedPlan,
      p_purchase_completed_at: args.completedAt,
    },
  );
  if (error) {
    throw new Error(`Failed to claim purchase email: ${error.message}`);
  }

  const claim = data as Record<string, unknown> | null;
  if (claim?.claimed !== true) {
    console.log("License purchase email already claimed", {
      eventId: args.eventId,
      sessionId: args.sessionId,
      emailStatus: claim?.email_status ?? null,
    });
    return;
  }

  const auditId = String(claim.event_id ?? "");
  const emailType = claim.email_type === "welcome" ? "welcome" : "returning";
  try {
    const apiKey = requiredEnv("RESEND_API_KEY");
    const from = requiredEnv("RESEND_FROM_EMAIL");
    const providerMessageId = await sendLicensePurchaseEmail({
      apiKey,
      from,
      to: args.secretaryEmail,
      type: emailType,
      secretaryName: args.secretaryName,
    });
    const { error: updateError } = await args.supabase
      .from("license_purchase_email_events")
      .update({
        email_status: "sent",
        provider_message_id: providerMessageId,
        email_error: null,
        email_sent_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", auditId);
    if (updateError) throw updateError;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await args.supabase
      .from("license_purchase_email_events")
      .update({
        email_status: "failed",
        email_error: message.slice(0, 1000),
        updated_at: new Date().toISOString(),
      })
      .eq("id", auditId);
    throw error;
  }
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}`);
  return value;
}
