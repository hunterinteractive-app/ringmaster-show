import { Webhook } from "npm:svix@1.76.0";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const statusForEvent = (eventType: string): string | null => {
  switch (eventType) {
    case "email.sent":
      return "sent";
    case "email.delivered":
      return "delivered";
    case "email.delivery_delayed":
      return "delivery_delayed";
    case "email.bounced":
      return "bounced";
    case "email.complained":
      return "complained";
    case "email.opened":
      return "opened";
    case "email.clicked":
      return "clicked";
    case "email.failed":
      return "failed";
    case "email.suppressed":
      return "suppressed";
    default:
      return null;
  }
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookSecret = Deno.env.get("RESEND_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!webhookSecret || !supabaseUrl || !serviceRoleKey) {
    return json({ error: "Webhook is not configured" }, 500);
  }

  const body = await request.text();
  const headers = {
    "svix-id": request.headers.get("svix-id") ?? "",
    "svix-timestamp": request.headers.get("svix-timestamp") ?? "",
    "svix-signature": request.headers.get("svix-signature") ?? "",
  };

  let event: { type?: string; data?: { email_id?: string; [key: string]: unknown } };
  try {
    event = new Webhook(webhookSecret).verify(body, headers) as typeof event;
  } catch {
    return json({ error: "Invalid webhook signature" }, 401);
  }

  const deliveryStatus = statusForEvent(event.type ?? "");
  const providerMessageId = event.data?.email_id?.trim();
  if (!deliveryStatus || !providerMessageId) return json({ ok: true, ignored: true });

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const errorMessage = ["email.bounced", "email.failed", "email.complained"].includes(event.type ?? "")
    ? JSON.stringify(event.data ?? {})
    : null;
  const { error } = await client
    .from("show_email_deliveries")
    .update({ delivery_status: deliveryStatus, error_message: errorMessage })
    .eq("provider_message_id", providerMessageId);
  if (error) return json({ error: "Unable to update delivery status" }, 500);

  return json({ ok: true });
});
