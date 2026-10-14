import { ownerMail, relayAuthorized, sendOwnerMail } from "./mail.ts";
const reply = (value: unknown, status = 200) =>
  new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
Deno.serve(async (req) => {
  if (req.method !== "POST") return reply({ error: "Use POST." }, 405);
  try {
    if (
      !await relayAuthorized(
        req.headers.get("Authorization") ?? "",
        Deno.env.get("BREEDER_SUPABASE_SERVICE_ROLE_KEY") ?? "",
      )
    ) {
      return reply({ error: "Server authorization required." }, 401);
    }
    const key = Deno.env.get("RESEND_API_KEY"),
      from = Deno.env.get("RESEND_FROM_EMAIL");
    if (!key || !from) {
      return reply({ error: "Email delivery unavailable." }, 503);
    }
    // Bound streams before parsing the base64 attachment.
    const reader = req.body?.getReader();
    if (!reader) return reply({ error: "Invalid request." }, 400);
    let size = 0;
    const chunks: Uint8Array[] = [];
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.length;
        if (size > 6000000) {
          await reader.cancel();
          return reply({ error: "Attachment too large." }, 413);
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const c of chunks) {
      bytes.set(c, offset);
      offset += c.length;
    }
    let body;
    try {
      body = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      return reply({ error: "Invalid JSON." }, 400);
    }
    if (body.action === "status") return reply({ configured: true });
    if (
      body.action !== "send" ||
      !/^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(body.request_id ?? "")
    ) return reply({ error: "Invalid request." }, 400);
    let payload;
    try {
      payload = ownerMail(body, from);
    } catch {
      return reply({ error: "Invalid mail or attachments." }, 400);
    }
    const id = await sendOwnerMail(payload, body.request_id, key);
    return reply({ provider_id: id, status: "accepted" });
  } catch {
    return reply({
      error: "Email was not confirmed. Retry with the same request ID.",
    }, 503);
  }
});
