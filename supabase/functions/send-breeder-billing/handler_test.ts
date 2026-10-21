let handler: (r: Request) => Promise<Response>;
const serve = Deno.serve;
(Deno as any).serve = (h: any) => {
  handler = h;
  return {};
};
await import("./index.ts");
Deno.serve = serve;
Deno.env.set(
  "BREEDER_SUPABASE_SERVICE_ROLE_KEY",
  "synthetic-private-relay-key",
);
Deno.env.set("RESEND_API_KEY", "synthetic-provider-key");
Deno.env.set("RESEND_FROM_EMAIL", "RingMaster <billing@example.test>");
const request = (body: any, authorized = true) =>
  new Request("https://example.test/relay", {
    method: "POST",
    headers: {
      Authorization: authorized
        ? "Bearer synthetic-private-relay-key"
        : "Bearer invalid",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
Deno.test("billing email relay rejects public callers before sending mail", async () => {
  const r = await handler(request({}, false));
  if (r.status !== 401) throw Error("public sender allowed");
});
Deno.test("billing email relay status checks configuration without sending mail", async () => {
  const r = await handler(request({ action: "status" }));
  if (r.status !== 200 || !(await r.json()).configured) {
    throw Error("status failed");
  }
});
Deno.test("billing relay rejects multiple recipient injection", async () => {
  const r = await handler(
    request({
      request_id: "e6102121-0000-4000-8000-000000000101",
      recipient: "a@example.test,b@example.test",
      message: "Your RingMaster Breeder price changes",
    }),
  );
  if (r.status !== 400) throw Error("invalid recipient accepted");
});
Deno.test("billing relay uses fixed subject and stable provider idempotency key", async () => {
  const original = globalThis.fetch;
  let count = 0;
  globalThis.fetch = (async (url: any, init: any) => {
    count++;
    if (String(url) !== "https://api.resend.com/emails") {
      throw Error("unexpected endpoint");
    }
    const body = JSON.parse(init.body);
    if (
      body.to.length !== 1 ||
      body.subject !== "Your RingMaster Breeder membership price is changing" ||
      init.headers["Idempotency-Key"] !==
        "breeder-price/e6102121-0000-4000-8000-000000000101"
    ) throw Error("wrong mail");
    return Response.json({ id: "provider-confirmation" });
  }) as typeof fetch;
  try {
    const r = await handler(
      request({
        request_id: "e6102121-0000-4000-8000-000000000101",
        recipient: "a@example.test",
        message: "Your RingMaster Breeder price changes",
      }),
    );
    if (
      r.status !== 200 ||
      (await r.json()).provider_id !== "provider-confirmation" || count !== 1
    ) throw Error("mail unconfirmed");
  } finally {
    globalThis.fetch = original;
  }
});
