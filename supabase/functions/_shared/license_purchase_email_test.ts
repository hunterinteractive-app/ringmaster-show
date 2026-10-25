/// <reference lib="deno.ns" />

import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  isCompletedLicenseCheckoutEvent,
  isCompletedSuccessfulLicensePurchase,
  licensePurchaseEmail,
  normalizeSecretaryEmail,
  sendLicensePurchaseEmail,
} from "./license_purchase_email.ts";

Deno.test("only completed paid purchases are eligible", () => {
  assertEquals(
    isCompletedLicenseCheckoutEvent("checkout.session.completed"),
    true,
  );
  assertEquals(
    isCompletedLicenseCheckoutEvent("checkout.session.async_payment_succeeded"),
    true,
  );
  assertEquals(
    isCompletedLicenseCheckoutEvent("checkout.session.expired"),
    false,
  );
  assertEquals(isCompletedLicenseCheckoutEvent("charge.refunded"), false);
  assertEquals(isCompletedSuccessfulLicensePurchase("complete", "paid"), true);
  assertEquals(
    isCompletedSuccessfulLicensePurchase("complete", "unpaid"),
    false,
  );
  assertEquals(isCompletedSuccessfulLicensePurchase("expired", "paid"), false);
  assertEquals(isCompletedSuccessfulLicensePurchase("open", "unpaid"), false);
});

Deno.test("secretary email normalization is conservative", () => {
  assertEquals(
    normalizeSecretaryEmail("  Secretary@Example.COM "),
    "secretary@example.com",
  );
  assertEquals(normalizeSecretaryEmail("not-an-email"), null);
});

Deno.test("convention receipts include the paid offer and escape any summary text", () => {
  const mail = licensePurchaseEmail(
    "returning",
    null,
    "6 tokens, including 2 bonus tokens. <script>",
  );
  assertStringIncludes(mail.subject, "Convention Purchase");
  assertStringIncludes(
    mail.html,
    "6 tokens, including 2 bonus tokens. &lt;script&gt;",
  );
  const welcome = licensePurchaseEmail(
    "welcome",
    "Buyer",
    "14 months unlimited, including 2 bonus months.",
  );
  assertStringIncludes(
    welcome.html,
    "14 months unlimited, including 2 bonus months.",
  );
});

Deno.test("first purchase renders the welcome onboarding email", () => {
  const email = licensePurchaseEmail("welcome", "Alex <Secretary>");
  assertEquals(
    email.subject,
    "Welcome to RingMaster Show — Let’s Get Started!",
  );
  assertStringIncludes(email.html, "https://show.ringmasterone.com");
  assertStringIncludes(
    email.html,
    "https://www.ringmasterone.com/help_secretaries.html",
  );
  assertStringIncludes(email.html, "Alex &lt;Secretary&gt;");
});

Deno.test("repeat purchase renders the shorter returning email", () => {
  const email = licensePurchaseEmail("returning");
  assertEquals(email.subject, "Your New RingMaster Show Token Is Ready");
  assertStringIncludes(email.html, "Your new token is now available");
  assertStringIncludes(email.html, "Show Secretary → More → Resources");
});

Deno.test("Resend request uses the repository email provider contract", async () => {
  let requestBody: Record<string, unknown> = {};
  const messageId = await sendLicensePurchaseEmail({
    apiKey: "test-key",
    from: "RingMaster Show <support@ringmasterone.com>",
    to: "secretary@example.com",
    type: "welcome",
    fetcher: async (_input, init) => {
      requestBody = JSON.parse(
        String(init && "body" in init ? init.body : "{}"),
      );
      return new Response(JSON.stringify({ id: "email-1" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    },
  });
  assertEquals(messageId, "email-1");
  assertEquals(requestBody.to, ["secretary@example.com"]);
});
