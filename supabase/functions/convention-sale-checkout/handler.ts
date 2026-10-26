import type Stripe from "npm:stripe@22.6.0";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.110.2";
import {
  checkoutMeasurement,
  conventionLocationFailure,
  type ConventionPlan,
  conventionPlans,
  conventionSecretaryQuestions,
  isConventionPlan,
  isUuid,
} from "../_shared/convention_sale.ts";
import { authErrorStatus } from "../_shared/request_fetch.ts";
import {
  type ConventionLocality,
  lookupConventionLocality,
} from "../_shared/convention_locality.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });

export function createConventionSaleHandler(deps: {
  stripe: Stripe;
  db: SupabaseClient;
  site: string;
  links?: Partial<Record<ConventionPlan, string>>;
  locality?: (
    latitude: number,
    longitude: number,
  ) => Promise<ConventionLocality>;
}) {
  const { stripe, db } = deps;
  async function locationRejection(body: Record<string, unknown>) {
    let settings: Record<string, unknown> | null = null;
    try {
      const result = await db.rpc("convention_sale_settings");
      if (!result.error) settings = result.data;
    } catch {
      // A settings outage must not grant eligibility or guess an outside area.
    }
    return json(conventionLocationFailure(body, settings), 400);
  }
  return async (req: Request) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
    if (req.method !== "POST") return json({ error: "Use POST" }, 405);
    try {
      const text = await req.text();
      if (text.length > 8192) return json({ error: "Request too large" }, 413);
      const body = JSON.parse(text) as Record<string, unknown>;
      if (!body || !["catalog", "checkout"].includes(String(body.action))) {
        return json({ error: "Unknown action" }, 400);
      }
      async function product(plan: ConventionPlan) {
        const linkId = deps.links?.[plan] ?? conventionPlans[plan].paymentLink;
        const [link, items] = await Promise.all([
          stripe.paymentLinks.retrieve(linkId),
          stripe.paymentLinks.listLineItems(linkId, { limit: 2 }),
        ]);
        const item = items.data[0];
        if (
          !link.active || items.has_more || items.data.length !== 1 ||
          item.quantity !== 1 ||
          !item.price?.active || item.price.recurring ||
          !item.price.unit_amount ||
          item.price.unit_amount !== item.amount_subtotal
        ) {
          throw new Error(
            "Token pricing is unavailable. Please visit the booth for help.",
          );
        }
        return { link, item, price: item.price };
      }
      if (body.action === "catalog") {
        const products = await Promise.all(
          (Object.keys(conventionPlans) as ConventionPlan[]).map(
            async (plan) => {
              const p = await product(plan);
              return {
                plan,
                amount: p.item.amount_subtotal,
                currency: p.item.currency,
                tax_inclusive: p.price.tax_behavior === "inclusive",
              };
            },
          ),
        );
        return json({ products });
      }
      const token =
        req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
      const { data: auth, error: authError } = await db.auth.getUser(token);
      if (authError || !auth.user) {
        return json(
          { error: "Sign in to your RingMaster account first." },
          authErrorStatus(authError),
        );
      }
      if (
        !auth.user.email_confirmed_at || auth.user.is_anonymous ||
        !auth.user.email
      ) return json({ error: "A verified RingMaster email is required." }, 403);
      if (!isConventionPlan(body.plan) || !isUuid(body.request_id)) {
        return json({ error: "Choose a token package and retry." }, 400);
      }
      let location;
      try {
        location = checkoutMeasurement(body);
      } catch {
        return await locationRejection(body);
      }
      const p = await product(body.plan);
      // Older open tabs have not shown the city/state retention notice. Leave
      // their original coordinate-only eligibility flow intact.
      if (body.location_notice_version === "2026-10-25-locality") {
        const check = await db.rpc("convention_sale_location_check", {
          p_id: body.request_id,
          p_user_id: auth.user.id,
          p_email: auth.user.email,
          p_plan: body.plan,
          p_latitude: location.latitude,
          p_longitude: location.longitude,
          p_accuracy: location.accuracy,
          p_measured_at: location.measured_at,
        });
        if (check.error) {
          const message = check.error.message;
          if (message.startsWith("A fresh")) {
            return await locationRejection(body);
          }
          return json({
            error: /^(The convention sale|A fresh|Too many|Checkout request)/
                .test(message)
              ? message
              : "Unable to verify this offer. Please retry or visit the booth for help.",
          }, 400);
        }
        if (check.data.lookup_needed) {
          let locality: ConventionLocality;
          try {
            locality = await (deps.locality ?? lookupConventionLocality)(
              location.latitude,
              location.longitude,
            );
          } catch {
            locality = { city: null, state: null, status: "unavailable" };
          }
          const saved = await db.rpc("convention_sale_location_result", {
            p_id: body.request_id,
            p_user_id: auth.user.id,
            p_city: locality.city,
            p_state: locality.state,
            p_status: locality.status,
          });
          if (saved.error) {
            console.error("Convention city/state could not save");
          }
        }
        if (!check.data.eligible) {
          return await locationRejection(body);
        }
      }
      const { data: claim, error } = await db.rpc(
        "convention_sale_claim_secretary",
        {
          p_id: body.request_id,
          p_user_id: auth.user.id,
          p_email: auth.user.email,
          p_plan: body.plan,
          p_latitude: location.latitude,
          p_longitude: location.longitude,
          p_accuracy: location.accuracy,
          p_measured_at: location.measured_at,
          p_price_id: p.price.id,
          p_amount_cents: p.price.unit_amount,
          p_currency: p.item.currency,
          p_livemode: p.link.livemode,
        },
      );
      if (error) {
        if (/^(A fresh|Your location)/.test(error.message)) {
          return await locationRejection(body);
        }
        const safeMessage =
          /^(The convention sale|A fresh|Your location|Location check|Too many|Checkout request)/
              .test(error.message)
            ? error.message
            : "Unable to verify this offer. Please retry or visit the booth for help.";
        return json({ error: safeMessage }, 400);
      }
      // Preserve the canonical link's tax behavior. Never turn on automatic tax
      // without an existing active registration on this Stripe account.
      if (p.link.automatic_tax.enabled) {
        const registrations = await stripe.tax.registrations.list({
          status: "active",
          limit: 1,
        });
        if (!registrations.data.length) {
          return json({
            error: "Checkout needs attention. Please visit the booth for help.",
          }, 503);
        }
      }
      const site = deps.site;
      const secretaryRecipient = claim.secretary_recipient === true;
      const bonus = body.plan === "unlimited"
        ? `Includes ${claim.bonus_months} bonus months (${
          12 + claim.bonus_months
        } months total).`
        : `Includes ${claim.bonus_tokens} bonus token${
          claim.bonus_tokens === 1 ? "" : "s"
        }.`;
      const session = await stripe.checkout.sessions.create({
        mode: "payment",
        line_items: [{ price: p.price.id, quantity: 1 }],
        customer_email: auth.user.email,
        client_reference_id: claim.id,
        metadata: {
          convention_claim_id: claim.id,
          ...(secretaryRecipient ? { convention_recipient: "secretary" } : {}),
        },
        custom_fields: secretaryRecipient
          ? conventionSecretaryQuestions()
          : undefined,
        automatic_tax: { enabled: p.link.automatic_tax.enabled },
        billing_address_collection: p.link.billing_address_collection,
        success_url: `${site}/#/convention-sale?purchase=${claim.id}`,
        cancel_url: `${site}/#/convention-sale?cancelled=1`,
        custom_text: {
          submit: {
            message: `${bonus} ${
              secretaryRecipient
                ? "Purchase and bonus go to the Show Secretary Email entered here."
                : "Credited to your signed-in RingMaster account."
            }`,
          },
        },
        integration_identifier: `ringmaster_convention_${
          claim.id.replaceAll("-", "").slice(0, 8).split("").map((c: string) =>
            "abcdefghijklmnop"[parseInt(c, 16)]
          ).join("")
        }`,
        // Fixed values keep the Stripe idempotency payload identical on retry.
        expires_at: Math.floor(Date.parse(claim.verified_at) / 1000) + 3600,
      }, { idempotencyKey: `convention-${claim.id}` });
      return json({ url: session.url, claim_id: claim.id });
    } catch (error) {
      // No request bodies, coordinates, payment details or provider payloads in logs.
      const message = error instanceof Error ? error.message : "";
      if (
        message.startsWith("A fresh") || message.startsWith("Token pricing")
      ) return json({ error: message }, 400);
      console.error(
        "Convention checkout unavailable",
        error instanceof Error ? error.name : "unknown",
      );
      return json({
        error:
          "Checkout is unavailable. Please retry or visit the booth for help.",
      }, 503);
    }
  };
}
