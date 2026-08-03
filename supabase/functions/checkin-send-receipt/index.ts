import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

type ReceiptContext = {
  delivery_id?: string;
  email?: string;
  show_name?: string;
  exhibitor_name?: string;
  checked_in_at?: string;
  already_sent?: boolean;
  in_progress?: boolean;
};

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const backend = serviceClient();
  let deliveryId = "";
  let delivered = false;
  try {
    const body = await request.json() as { session_token?: string };
    const sessionToken = body.session_token?.trim() ?? "";
    if (!sessionToken) return jsonResponse({ error: "Check-in session is required." }, 400);

    const { data, error } = await backend.rpc("claim_checkin_receipt_delivery", {
      p_session_token: sessionToken,
    });
    if (error || !data) throw new Error("Receipt email is not available.");
    const context = data as ReceiptContext;
    if (context.already_sent) return jsonResponse({ status: "already_sent" });
    if (context.in_progress) return jsonResponse({ status: "in_progress" });

    deliveryId = String(context.delivery_id ?? "");
    const recipient = String(context.email ?? "").trim();
    if (!deliveryId || !recipient) throw new Error("Receipt email is not available.");

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requiredEnv("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: requiredEnv("RESEND_FROM_EMAIL"),
        to: [recipient],
        subject: `RingMaster Check-In Confirmation — ${text(context.show_name)}`,
        html: receiptHtml(context),
      }),
    });
    const resend = await response.json().catch(() => ({})) as { id?: string };
    if (!response.ok || !resend.id) throw new Error("Unable to send the receipt email.");
    delivered = true;

    const { error: finalizeError } = await backend.rpc("finalize_checkin_receipt_delivery", {
      p_delivery_id: deliveryId,
      p_provider_message_id: resend.id,
      p_failure_message: null,
    });
    if (finalizeError) throw new Error("Unable to record receipt delivery.");
    return jsonResponse({ status: "sent" });
  } catch (error) {
    if (deliveryId && !delivered) {
      await backend.rpc("finalize_checkin_receipt_delivery", {
        p_delivery_id: deliveryId,
        p_provider_message_id: null,
        p_failure_message: errorMessage(error),
      }).catch(() => undefined);
    }
    return jsonResponse({ error: "We could not send the receipt email." }, 400);
  }
});

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error("Receipt email is not configured.");
  return value;
}

function text(value: unknown): string {
  return String(value ?? "RingMaster Show").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character] ?? character));
}

function receiptHtml(context: ReceiptContext): string {
  const showName = text(context.show_name);
  const exhibitorName = text(context.exhibitor_name || "Exhibitor");
  const checkedInAt = context.checked_in_at
    ? new Date(context.checked_in_at).toLocaleString("en-US", { dateStyle: "long", timeStyle: "short" })
    : "today";
  return `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#192a50;line-height:1.5">
    <h2 style="color:#3c1d80">Check-In Confirmed</h2>
    <p>Hello ${exhibitorName},</p>
    <p>Your exhibitor check-in for <strong>${showName}</strong> was completed on ${text(checkedInAt)}.</p>
    <p>Please contact the show secretary if you need help with your entries.</p>
    <p>— RingMaster Show</p>
  </body></html>`;
}
