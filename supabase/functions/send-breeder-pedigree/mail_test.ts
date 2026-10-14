import { ownerMail, relayAuthorized, sendOwnerMail } from "./mail.ts";
function assert(value: unknown) {
  if (!value) throw new Error("Assertion failed");
}
const body = {
  owner_name: "Family Owner",
  owner_email: "owner@example.com",
  recipient: "buyer@example.com",
  export_json: {
    format: "ringmaster-pedigree",
    version: 1,
    pedigree: { animal: { name: "Midnight" } },
  },
  pdf: btoa("%PDF-1.4 test"),
};
Deno.test("owner display name uses verified sender mailbox and owner reply address", () => {
  const mail = ownerMail(body, "RingMaster <support@ringmasterone.com>");
  assert(mail.from === '"Family Owner" <support@ringmasterone.com>');
  assert(mail.reply_to === "owner@example.com");
  assert(mail.to[0] === "buyer@example.com");
  assert(mail.attachments.length === 2);
  assert(
    mail.attachments[0].filename === "pedigree.pdf" &&
      mail.attachments[1].filename === "pedigree.json",
  );
  assert(
    JSON.parse(atob(mail.attachments[1].content)).pedigree.animal.name ===
      "Midnight",
  );
});
Deno.test("sender display name cannot inject email headers", () => {
  const mail = ownerMail({
    ...body,
    owner_name: "Owner\r\nBcc: hacker@example.com",
  }, "support@ringmasterone.com");
  assert(!mail.from.includes("\n") && !mail.from.includes("\r"));
});
Deno.test("retry keeps provider idempotency key and accepts only confirmed provider IDs", async () => {
  const calls: RequestInit[] = [];
  const fake = (async (_input: unknown, init: RequestInit) => {
    calls.push(init);
    return Response.json({ id: "provider-id" });
  }) as typeof fetch;
  const mail = ownerMail(body, "support@ringmasterone.com");
  assert(await sendOwnerMail(mail, "request", "key", fake) === "provider-id");
  await sendOwnerMail(mail, "request", "key", fake);
  assert(JSON.stringify(calls[0]) === JSON.stringify(calls[1]));
  assert(
    (calls[0].headers as Record<string, string>)["Idempotency-Key"] ===
      "breeder-pedigree/request",
  );
});
Deno.test("provider failure does not report acceptance", async () => {
  let failed = false;
  try {
    await sendOwnerMail(
      ownerMail(body, "support@ringmasterone.com"),
      "request",
      "key",
      (async () => new Response("failed", { status: 503 })) as typeof fetch,
    );
  } catch {
    failed = true;
  }
  assert(failed);
});

Deno.test("relay rejects user/invalid tokens and requires the configured bridge credential", async () => {
  assert(!await relayAuthorized("Bearer invalid", "server-secret"));
  assert(!await relayAuthorized("", "server-secret"));
  assert(!await relayAuthorized("Bearer anything", ""));
  assert(await relayAuthorized("Bearer server-secret", "server-secret"));
});
