import { sendInvitationEmail } from "./email.ts";
Deno.test("invitation delivery uses a stable idempotency key and separate login instructions", async () => {
  let calls = 0;
  const fetcher: typeof fetch = (_url, init) => {
    calls++;
    if (
      new Headers(init?.headers).get("Idempotency-Key") !==
        "household-invitation-test-id"
    ) throw new Error("Missing idempotency key");
    const body = JSON.parse(String(init?.body));
    if (
      body.to[0] !== "member@example.invalid" ||
      !body.text.includes("admin permissions are separate") ||
      !body.text.includes("own login code")
    ) throw new Error("Incorrect invitation contents");
    return Promise.resolve(new Response("{}", { status: 200 }));
  };
  const args = {
    id: "test-id",
    apiKey: "fixture",
    from: "fixture@example.invalid",
    to: "member@example.invalid",
    inviter: "owner@example.invalid",
    fetcher,
  };
  await sendInvitationEmail(args);
  await sendInvitationEmail(args);
  if (calls !== 2) throw new Error("Expected two idempotent requests");
});
Deno.test("failed email delivery is surfaced for retry", async () => {
  try {
    await sendInvitationEmail({
      id: "test-id",
      apiKey: "fixture",
      from: "fixture@example.invalid",
      to: "member@example.invalid",
      inviter: "owner@example.invalid",
      fetcher: () => Promise.resolve(new Response("{}", { status: 503 })),
    });
  } catch (e) {
    if (String(e).includes("could not be sent")) return;
    throw e;
  }
  throw new Error("Failure was swallowed");
});
