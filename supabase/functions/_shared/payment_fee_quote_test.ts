import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { calculatePaymentFeeQuote } from "./payment.ts";

Deno.test("Square exhibitor-paid quote grosses up 3.3% + 30 cents and platform fee", () => {
  const quote = calculatePaymentFeeQuote({
    baseTotalCents: 200,
    passFeeToExhibitor: true,
    platformFeePercent: 0.02,
    processingFeePercent: 3.3,
    processingFeeFixedCents: 30,
  });
  assertEquals(quote.onlineFeeCents, 44);
  assertEquals(quote.expectedAmountCents, 244);
  assertEquals(quote.platformFeeCents, 5);
});

Deno.test("club-absorbed quote does not increase buyer total", () => {
  const quote = calculatePaymentFeeQuote({
    baseTotalCents: 200,
    passFeeToExhibitor: false,
    platformFeePercent: 0.02,
    processingFeePercent: 3.3,
    processingFeeFixedCents: 30,
  });
  assertEquals(quote.onlineFeeCents, 0);
  assertEquals(quote.expectedAmountCents, 200);
  assertEquals(quote.platformFeeCents, 4);
});

Deno.test("invalid combined rate is rejected", () => {
  assertThrows(() =>
    calculatePaymentFeeQuote({
      baseTotalCents: 200,
      passFeeToExhibitor: true,
      platformFeePercent: 60,
      processingFeePercent: 40,
      processingFeeFixedCents: 30,
    })
  );
});
