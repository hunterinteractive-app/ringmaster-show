import { handleClubReportBatch } from "./handler.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
async function run(body: Record<string, unknown>) {
  const savedFetch = globalThis.fetch;
  const keys = ["SUPABASE_URL", "SUPABASE_ANON_KEY"];
  const previous = keys.map((key) => Deno.env.get(key));
  Deno.env.set(keys[0], "https://fixture.invalid");
  Deno.env.set(keys[1], "test-anon");
  const sent: any[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    assert(
      req.url === "https://fixture.invalid/functions/v1/send-report-email",
    );
    assert(req.headers.get("authorization") === "Bearer test-user");
    const payload = await req.json();
    sent.push(payload);
    return new Response(
      JSON.stringify({
        ok: true,
        already_sent: payload.to === "old@example.test",
      }),
    );
  }) as typeof fetch;
  try {
    const response = await handleClubReportBatch(
      new Request("https://fixture.invalid/batch", {
        method: "POST",
        headers: { Authorization: "Bearer test-user" },
        body: JSON.stringify({
          show_id: "show",
          deliveries: [
            {
              to: "old@example.test",
              artifact_ids: ["a"],
              message: "Thank you.",
            },
            {
              to: "new@example.test",
              artifact_ids: ["b"],
              message: "Thank you.",
            },
          ],
          ...body,
        }),
      }),
    );
    return { status: response.status, body: await response.json(), sent };
  } finally {
    globalThis.fetch = savedFetch;
    keys.forEach((key, i) =>
      previous[i] === undefined
        ? Deno.env.delete(key)
        : Deno.env.set(key, previous[i]!)
    );
  }
}
Deno.test("bulk resend cannot start any child send without an explanation", async () => {
  for (const resend_message of ["", "  \n "]) {
    const result = await run({ force_resend: true, resend_message });
    assert(result.status === 400 && result.sent.length === 0);
  }
});
Deno.test("bulk resend explicitly forwards trimmed explanation and bulk scope to every recipient", async () => {
  const result = await run({
    force_resend: true,
    resend_message: " Corrected names. ",
  });
  assert(result.status === 200 && result.sent.length === 2);
  assert(
    result.sent.every((body) =>
      body.force_resend === true && body.resend_scope === "bulk" &&
      body.message === "Corrected names."
    ),
  );
});
Deno.test("ordinary batch notes never force resend and skips are not counted as new emails", async () => {
  const result = await run({});
  assert(
    result.sent.every((body) =>
      body.force_resend === false && body.resend_scope === "bulk" &&
      body.message === "Thank you."
    ),
  );
  assert(
    result.body.sent_count === 1 && result.body.already_sent_count === 1 &&
      result.body.failed_count === 0,
  );
});
