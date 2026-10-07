export type Confirmation = {
  charges?: { label: string; amount_cents: number }[];
  to: string;
  show_name: string;
  exhibitors: string;
  entry_count: number;
  paid_cents: number;
  balance_due_cents: number;
  currency: string;
  auto_checkin: boolean;
  payment_timing: string;
};
const escape = (value: unknown) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (
      c,
    ) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[c]!),
  );
export function confirmationEmail(data: Confirmation) {
  if (
    !data.to || !Number.isInteger(data.entry_count) || data.entry_count < 1 ||
    !Number.isSafeInteger(data.paid_cents) || data.paid_cents < 0 ||
    !Number.isSafeInteger(data.balance_due_cents) || data.balance_due_cents < 0
  ) {
    throw new Error("Invalid confirmation snapshot");
  }
  const money = (cents: number) =>
    new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: data.currency,
    }).format(cents / 100) + ` ${data.currency}`;
  const charges = (data.charges ?? []).filter((line) =>
    line.amount_cents !== 0
  );
  if (
    charges.some((line) =>
      !Number.isSafeInteger(line.amount_cents) || !line.label
    )
  ) {
    throw new Error("Invalid confirmation charges");
  }
  const chargeText = charges.map((line) =>
    `${line.label}: ${money(line.amount_cents)}`
  ).join("\n");
  const chargeHtml = charges.map((line) =>
    `<strong>${escape(line.label)}:</strong> ${
      escape(money(line.amount_cents))
    }`
  ).join("<br>");
  const checkin = data.auto_checkin === true
    ? "Your check-in sheet will be emailed after entries close."
    : "";
  const paymentNote =
    data.balance_due_cents > 0 && data.payment_timing === "at_show"
      ? "Your remaining balance is payable at the show."
      : "";
  const text =
    `Hello,\n\nYour entries for ${data.show_name} have been successfully submitted.\n\nExhibitors: ${data.exhibitors}\nEntries submitted: ${data.entry_count}\n${chargeText}\nPaid: ${
      money(data.paid_cents)
    }\nBalance due: ${
      money(data.balance_due_cents)
    }\n${paymentNote}\n\nTo review your entries, sign in at https://show.ringmasterone.com/, open My Entries, and select the show.\n\n${checkin}\n\nThank you!\nRingMaster Show`;
  return {
    from: "RingMaster Show <noreply@ringmasterone.com>",
    to: [data.to],
    reply_to: "support@ringmasterone.com",
    subject: `Your entries are confirmed — ${data.show_name}`,
    text,
    html:
      `<div style="font-family:Arial,sans-serif;line-height:1.6"><p>Hello,</p><p>Your entries for <strong>${
        escape(data.show_name)
      }</strong> have been successfully submitted.</p><p><strong>Exhibitors:</strong> ${
        escape(data.exhibitors)
      }<br><strong>Entries submitted:</strong> ${data.entry_count}<br>${
        chargeHtml ? chargeHtml + "<br>" : ""
      }<strong>Paid:</strong> ${
        escape(money(data.paid_cents))
      }<br><strong>Balance due:</strong> ${
        escape(money(data.balance_due_cents))
      }</p>${
        paymentNote ? `<p>${paymentNote}</p>` : ""
      }<p>To review your entries, <a href="https://show.ringmasterone.com/">sign in to RingMaster Show</a>, open <strong>My Entries</strong>, and select the show.</p>${
        checkin ? `<p>${checkin}</p>` : ""
      }<p>Thank you!<br>RingMaster Show</p></div>`,
  };
}
