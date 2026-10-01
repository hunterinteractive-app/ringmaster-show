import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
  assertThrows,
} from "jsr:@std/assert@1";
import { type Confirmation, confirmationEmail } from "./email.ts";
import { sendConfirmation } from "./send.ts";
const snapshot: Confirmation = {
  to: "account@example.com",
  show_name: "Test & Show",
  exhibitors: "Parent, Youth",
  entry_count: 3,
  paid_cents: 0,
  balance_due_cents: 2400,
  currency: "USD",
  auto_checkin: false,
  payment_timing: "at_show",
};
Deno.test("one household confirmation with balance and entry instructions", () => {
  const email = confirmationEmail(snapshot);
  assertEquals(email.to, ["account@example.com"]);
  assertStringIncludes(email.text, "Parent, Youth");
  assertStringIncludes(email.text, "Balance due: $24.00 USD");
  assertStringIncludes(email.text, "Paid: $0.00 USD");
  assertStringIncludes(email.text, "My Entries");
  assertEquals(email.text.includes("check-in sheet"), false);
  assertEquals(email.html.includes("check-in sheet"), false);
});
Deno.test("paid confirmation includes check-in promise only when enabled", () => {
  const email = confirmationEmail({
    ...snapshot,
    paid_cents: 2575,
    balance_due_cents: 0,
    auto_checkin: true,
    payment_timing: "online",
  });
  assertStringIncludes(email.text, "Paid: $25.75 USD");
  assertStringIncludes(email.text, "Balance due: $0.00 USD");
  assertStringIncludes(
    email.text,
    "Your check-in sheet will be emailed after entries close.",
  );
  assertStringIncludes(
    email.html,
    "Your check-in sheet will be emailed after entries close.",
  );
  assertEquals(email.text.includes("payable at the show"), false);
});
Deno.test("HTML escapes names and rejects invalid amounts", () => {
  const email = confirmationEmail({
    ...snapshot,
    exhibitors: '<script> & "Test"',
  });
  assertStringIncludes(email.html, "&lt;script&gt; &amp; &quot;Test&quot;");
  assertThrows(() => confirmationEmail({ ...snapshot, paid_cents: NaN }));
  assertThrows(() => confirmationEmail({ ...snapshot, balance_due_cents: -1 }));
});
Deno.test("delivery retries use identical payload and cart idempotency key", async () => {
  const requests: RequestInit[] = [];
  const mock: typeof fetch = (_url, init) => {
    requests.push(init!);
    return Promise.resolve(Response.json({ id: "receipt" }));
  };
  const payload = confirmationEmail(snapshot);
  assertEquals(
    await sendConfirmation("test", "cart-1", payload, mock),
    "receipt",
  );
  await sendConfirmation("test", "cart-1", payload, mock);
  assertEquals(requests[0].body, requests[1].body);
  assertEquals(
    new Headers(requests[0].headers).get("Idempotency-Key"),
    "entry-confirmation/cart-1",
  );
  assertEquals(
    new Headers(requests[1].headers).get("Idempotency-Key"),
    "entry-confirmation/cart-1",
  );
});
Deno.test("provider errors and missing receipts remain failures", async () => {
  await assertRejects(() =>
    sendConfirmation(
      "test",
      "cart",
      {},
      () =>
        Promise.resolve(Response.json({ message: "limited" }, { status: 429 })),
    )
  );
  await assertRejects(() =>
    sendConfirmation(
      "test",
      "cart",
      {},
      () => Promise.resolve(Response.json({})),
    )
  );
});

Deno.test("applicable fees show custom labels and zero fees stay hidden", () => {
  const email = confirmationEmail({
    ...snapshot,
    charges: [
      { label: "Entry fees", amount_cents: 2000 },
      { label: "Houston Exhibitor Fee", amount_cents: 400 },
      { label: "Online payment fee", amount_cents: 150 },
      { label: "Not applicable fee", amount_cents: 0 },
      { label: "Discount", amount_cents: -100 },
    ],
  });
  for (const body of [email.text, email.html]) {
    assertStringIncludes(body, "Houston Exhibitor Fee");
    assertStringIncludes(body, "$4.00 USD");
    assertStringIncludes(body, "Online payment fee");
    assertEquals(body.includes("Not applicable fee"), false);
    assertStringIncludes(body, "-$1.00 USD");
  }
  const noFees = confirmationEmail(snapshot);
  assertEquals(noFees.text.includes("Online payment fee"), false);
  assertEquals(noFees.text.includes("Exhibitor Fee"), false);
});
