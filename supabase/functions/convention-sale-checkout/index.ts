import Stripe from "npm:stripe@22.6.0";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import { createConventionSaleHandler } from "./handler.ts";
import {
  type ConventionPlan,
  conventionPlans,
} from "../_shared/convention_sale.ts";

Deno.serve(createConventionSaleHandler({
  stripe: new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
    apiVersion: "2026-08-26.dahlia",
    maxNetworkRetries: 2,
    timeout: 10000,
  }),
  db: createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  ),
  site: Deno.env.get("CONVENTION_SITE_ORIGIN") ??
    "https://show.ringmasterone.com",
  links: Object.fromEntries(
    (Object.keys(conventionPlans) as ConventionPlan[]).map(
      (plan) => [
        plan,
        Deno.env.get(`CONVENTION_${plan.toUpperCase()}_PAYMENT_LINK_ID`) ??
          conventionPlans[plan].paymentLink,
      ],
    ),
  ),
}));
