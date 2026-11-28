import { handleSweepstakesRequestCode } from "./handler.ts";

async function requestCode(options: {
  assignment?: boolean;
  tester?: boolean;
  lookupFails?: boolean;
} = {}) {
  const environment = {
    SUPABASE_URL: "https://sweepstakes-fixture.invalid",
    SUPABASE_SERVICE_ROLE_KEY: "fixture-service-role",
    RESEND_API_KEY: "fixture-resend-key",
    RESEND_FROM_EMAIL: "portal@example.invalid",
  };
  const previous = Object.fromEntries(
    Object.keys(environment).map((key) => [key, Deno.env.get(key)]),
  );
  for (const [key, value] of Object.entries(environment)) {
    Deno.env.set(key, value);
  }

  const fetch = globalThis.fetch;
  let generated = 0;
  let sent = 0;
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    if (url.hostname === "api.resend.com" && url.pathname === "/emails") {
      sent++;
      const body = await request.json();
      if (body.to?.[0] !== "chair@example.invalid") {
        throw new Error("Incorrect recipient");
      }
      return Response.json({ id: "fixture-message" });
    }
    if (url.hostname !== "sweepstakes-fixture.invalid") {
      throw new Error(`Unexpected network request to ${url.hostname}`);
    }
    if (url.pathname === "/auth/v1/admin/generate_link") {
      generated++;
      return Response.json({
        email: "chair@example.invalid",
        email_otp: "123456",
        verification_type: "magiclink",
      });
    }
    const table = url.pathname.split("/").pop();
    if (
      table !== "sweepstakes_portal_assignments" &&
      table !== "sweepstakes_portal_testers"
    ) {
      throw new Error(`Unexpected table ${table}`);
    }
    const isAssignments = table === "sweepstakes_portal_assignments";
    if (isAssignments && options.lookupFails) {
      return Response.json({ code: "XX000" }, { status: 500 });
    }
    const hasAccess = isAssignments ? options.assignment : options.tester;
    return Response.json(hasAccess ? [{ id: "verified-access" }] : []);
  };

  try {
    const response = await handleSweepstakesRequestCode(
      new Request("https://sweepstakes-fixture.invalid", {
        method: "POST",
        body: JSON.stringify({ email: " Chair@Example.Invalid " }),
      }),
    );
    return {
      status: response.status,
      body: await response.json(),
      generated,
      sent,
    };
  } finally {
    globalThis.fetch = fetch;
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("unassigned emails receive an access error before code generation or delivery", async () => {
  const result = await requestCode();
  if (
    result.status !== 403 || result.body.code !== "portal_access_required" ||
    result.generated !== 0 || result.sent !== 0
  ) throw new Error(JSON.stringify(result));
});

Deno.test("a failed access lookup returns a retryable error instead of an access denial", async () => {
  const result = await requestCode({ lookupFails: true });
  if (
    result.status !== 503 || result.body.code === "portal_access_required" ||
    result.generated !== 0 || result.sent !== 0
  ) throw new Error(JSON.stringify(result));
});

Deno.test("an active assignment or tester record can still receive a code", async () => {
  for (const options of [{ assignment: true }, { tester: true }]) {
    const result = await requestCode(options);
    if (
      result.status !== 200 || result.body.ok !== true ||
      result.generated !== 1 || result.sent !== 1
    ) throw new Error(JSON.stringify(result));
  }
});
