import { currentCartBalances } from "./balances.ts";
import { calculatePaymentFeeQuote } from "../_shared/payment.ts";

Deno.test("removed exhibitor's balance is excluded and current entries are not double counted", () => {
  const rows = currentCartBalances([
    { exhibitor_id: "removed", balance_due_cents: 500, currency: "cad" },
    { exhibitor_id: "current", balance_due_cents: 1000, currency: "usd" },
  ], [{ exhibitor_id: "current" }, { exhibitor_id: "current" }]);
  const quote = calculatePaymentFeeQuote({
    baseTotalCents: rows.reduce((sum, row) => sum + row.balance_due_cents!, 0),
    passFeeToExhibitor: true,
    platformFeePercent: 0.02,
    processingFeePercent: 0.029,
    processingFeeFixedCents: 30,
  });
  if (
    rows.length !== 1 || quote.expectedAmountCents !== 1084 ||
    quote.onlineFeeCents !== 84
  ) {
    throw new Error(JSON.stringify(quote));
  }
});
Deno.test("all current exhibitors and fee carriers remain included; empty cart has no balance", () => {
  const balances = [{ exhibitor_id: "animal", balance_due_cents: 1000 }, {
    exhibitor_id: "fee-carrier",
    balance_due_cents: 500,
  }];
  if (currentCartBalances(balances, balances).length !== 2) {
    throw new Error("Lost fee carrier");
  }
  if (currentCartBalances(balances, []).length !== 0) {
    throw new Error("Stale total");
  }
});
