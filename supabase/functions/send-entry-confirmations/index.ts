import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import { type Confirmation, confirmationEmail } from "./email.ts";

import { sendConfirmation } from "./send.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const key = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "")
    .trim();
  if (!key) return new Response("Unauthorized", { status: 401 });
  // Validate the credential against the service-only queue, including rotated keys.
  const db = createClient(Deno.env.get("SUPABASE_URL") ?? "", key);
  const { error: denied } = await db.from("entry_confirmation_emails").select(
    "cart_id",
  ).limit(0);
  if (denied) return new Response("Unauthorized", { status: 401 });
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    return new Response("Email service unavailable", { status: 503 });
  }
  const token = crypto.randomUUID();
  const { data: jobs, error } = await db.rpc(
    "claim_entry_confirmation_emails",
    { p_token: token },
  );
  if (error) {
    return Response.json({ error: "Unable to claim confirmations" }, {
      status: 500,
    });
  }
  let sent = 0, failed = 0, skipped = 0;
  for (const job of jobs ?? []) {
    const update = (values: Record<string, unknown>) =>
      db.from("entry_confirmation_emails")
        .update(values).eq("cart_id", job.cart_id).eq("lease_token", token).eq(
          "status",
          "pending",
        ).select("cart_id").single();
    try {
      const { data: show, error: showError } = await db.from("shows").select(
        "is_test,email_sending_disabled",
      )
        .eq("id", job.show_id).single();
      if (showError) throw showError;
      if (show.is_test || show.email_sending_disabled) {
        const { error } = await update({
          status: "skipped",
          lease_until: null,
        });
        if (error) throw error;
        skipped++;
        continue;
      }
      // Freeze the exact payload before the first send so retries use identical
      // content and the same provider idempotency key across worker deployments.
      const payload = job.email_payload ??
        confirmationEmail(job.snapshot as Confirmation);
      const { error: saveError } = await update({ email_payload: payload });
      if (saveError) throw saveError;
      const messageId = await sendConfirmation(apiKey, job.cart_id, payload);
      const { error: receiptError } = await update({
        status: "sent",
        provider_message_id: messageId,
        sent_at: new Date().toISOString(),
        last_error: null,
        lease_until: null,
      });
      if (receiptError) throw receiptError;
      sent++;
    } catch (error) {
      failed++;
      await update({
        last_error: String(error).slice(0, 500),
        lease_until: null,
      });
    }
    await new Promise((resolve) => setTimeout(resolve, 600));
  }
  return Response.json({ sent, failed, skipped });
});
