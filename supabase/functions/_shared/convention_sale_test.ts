import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  checkoutMeasurement,
  conventionFulfillmentParams,
  isConventionPlan,
} from "./convention_sale.ts";

const id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
function paidSession() {
  return {
    id: "cs_convention_test",
    status: "complete",
    payment_status: "paid",
    livemode: false,
    created: 1793030400,
    amount_subtotal: 5000,
    amount_total: 5000,
    currency: "usd",
    client_reference_id: id,
    metadata: { convention_claim_id: id },
    line_items: {
      data: [{
        quantity: 1,
        price: {
          id: "price_tokens",
          unit_amount: 5000,
          tax_behavior: "exclusive",
        },
      }],
    },
  };
}
Deno.test("checkout accepts only the three token products", () => {
  for (const plan of ["single_show", "four_shows", "unlimited"]) {
    assertEquals(isConventionPlan(plan), true);
  }
  for (const plan of ["__proto__", "toString", "secretary_license", null]) {
    assertEquals(isConventionPlan(plan), false);
  }
});
Deno.test("location must be finite, recent and accurate", () => {
  const now = Date.parse("2026-10-26T18:00:00Z");
  const valid = {
    latitude: 39.4861,
    longitude: -119.7911,
    accuracy: 30,
    measured_at: new Date(now).toISOString(),
  };
  assertEquals(checkoutMeasurement(valid, now), valid);
  for (
    const invalid of [
      { latitude: NaN },
      { longitude: Infinity },
      { latitude: 91 },
      { longitude: -181 },
      { accuracy: 251 },
      { accuracy: -1 },
      { accuracy: "10" },
      { measured_at: new Date(now - 61000).toISOString() },
      { measured_at: new Date(now + 31000).toISOString() },
    ]
  ) assertThrows(() => checkoutMeasurement({ ...valid, ...invalid }, now));
});
Deno.test("paid session resolves only the server-created claim and exact line item", () => {
  const result = conventionFulfillmentParams(paidSession());
  assertEquals(result.p_claim_id, id);
  assertEquals(result.p_price_id, "price_tokens");
  assertEquals(result.p_amount_cents, 5000);
  assertEquals(result.p_livemode, false);
});
Deno.test("tax-inclusive purchases verify the total without rejecting embedded sales tax", () => {
  const session = paidSession();
  session.amount_subtotal = 4600;
  session.line_items.data[0].price.tax_behavior = "inclusive";
  assertEquals(conventionFulfillmentParams(session).p_amount_cents, 5000);
  session.line_items.data[0].price.tax_behavior = "exclusive";
  assertEquals(conventionFulfillmentParams(session).p_amount_cents, 4600);
});
Deno.test("unpaid, incomplete, substituted and multi-item sessions cannot fulfill", () => {
  const invalid = [
    { ...paidSession(), payment_status: "unpaid" },
    { ...paidSession(), status: "open" },
    { ...paidSession(), client_reference_id: "another-account" },
    { ...paidSession(), metadata: { convention_claim_id: "not-a-claim" } },
    { ...paidSession(), amount_subtotal: 0 },
    { ...paidSession(), amount_subtotal: null },
    {
      ...paidSession(),
      line_items: { data: [{ quantity: 2, price: { id: "price_tokens" } }] },
    },
    {
      ...paidSession(),
      line_items: { has_more: true, data: paidSession().line_items.data },
    },
    { ...paidSession(), line_items: { data: [] } },
  ];
  for (const session of invalid) {
    assertThrows(() => conventionFulfillmentParams(session));
  }
});
