import { relayAuthorized } from "../send-breeder-pedigree/mail.ts";
Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "Use POST" }, { status: 405 });
  }
  try {
    if (
      !await relayAuthorized(
        req.headers.get("Authorization") ?? "",
        Deno.env.get("BREEDER_SUPABASE_SERVICE_ROLE_KEY") ?? "",
      )
    ) {
      return Response.json({ error: "Server authorization required" }, {
        status: 401,
      });
    }
    const key = Deno.env.get("RESEND_API_KEY"),
      from = Deno.env.get("RESEND_FROM_EMAIL");
    if (!key || !from) {
      return Response.json({ error: "Email unavailable" }, { status: 503 });
    }
    if (
      req.headers.get("content-length") &&
      Number(req.headers.get("content-length")) > 10000
    ) return Response.json({ error: "Too large" }, { status: 413 });
    const raw = await req.text();
    if (raw.length > 10000) {
      return Response.json({ error: "Too large" }, { status: 413 });
    }
    const body = JSON.parse(raw);
    if (body.action === "status") return Response.json({ configured: true });
    if (
      !/^[a-f\d]{8}(-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(
        body.request_id ?? "",
      ) || typeof body.recipient !== "string" || body.recipient.length > 254 ||
      !/^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$/.test(body.recipient) ||
      typeof body.message !== "string" || body.message.length > 6000 ||
      !body.message.includes("Your RingMaster Breeder")
    ) {
      return Response.json({ error: "Invalid billing notice" }, {
        status: 400,
      });
    }
    const result = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `breeder-price/${body.request_id}`,
      },
      body: JSON.stringify({
        from,
        to: [body.recipient],
        subject: "Your RingMaster Breeder membership price is changing",
        text: body.message,
      }),
      signal: AbortSignal.timeout(20000),
    });
    const data = await result.json();
    if (!result.ok || typeof data.id !== "string") throw Error("Not confirmed");
    return Response.json({ provider_id: data.id, status: "accepted" });
  } catch {
    return Response.json({
      error: "Email acceptance not confirmed. Retry the same request.",
    }, { status: 503 });
  }
});
