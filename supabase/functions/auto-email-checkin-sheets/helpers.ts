export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object") {
    const e = error as Record<string, unknown>;
    return [e.code, e.message, e.details, e.hint].filter(Boolean).join(": ") ||
      JSON.stringify(e);
  }
  return String(error);
}

// Report RPCs omit the account number. Resolve the actual exhibitor on each
// entry, including separately numbered exhibitors in the same household.
export async function enrichExhibitorNumbers(
  entries: Record<string, unknown>[],
  fetchExhibitors: (ids: string[]) => Promise<Record<string, unknown>[]>,
): Promise<void> {
  const ids = [
    ...new Set(
      entries.map((e) => String(e.exhibitor_id ?? "").trim()).filter(Boolean),
    ),
  ];
  const numbers = new Map<string, string>();
  for (let from = 0; from < ids.length; from += 100) {
    const rows = await fetchExhibitors(ids.slice(from, from + 100));
    for (const row of rows) {
      const number = String(row.exhibitor_number ?? "").trim();
      if (number) numbers.set(String(row.id), number);
    }
  }
  for (const entry of entries) {
    const number = numbers.get(String(entry.exhibitor_id ?? "").trim());
    if (number) entry.exhibitor_number = number;
  }
}
// Keep fetching until an empty page: the API may cap rows below our request.
export async function loadAllPages<T>(
  fetchPage: (from: number, to: number) => Promise<T[]>,
): Promise<T[]> {
  const rows: T[] = [];
  for (;;) {
    const page = await fetchPage(rows.length, rows.length + 499);
    if (!page.length) return rows;
    rows.push(...page);
  }
}
export function retryWindowOpen(
  firstAttempt: string,
  now = Date.now(),
): boolean {
  return now - Date.parse(firstAttempt) < 23 * 60 * 60 * 1000;
}

export const waveSheetNote =
  "This check-in sheet includes only your animals in this wave. If you have animals entered in other waves, you’ll receive a separate check-in sheet as each wave’s check-in approaches. You can view all your entries anytime in the Entries tab of your account.";

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[c]!));
}

export function buildCheckinEmailHtml({
  name,
  showName,
  waveLabel,
  checkinUrl,
}: {
  name: string;
  showName: string;
  waveLabel?: string;
  checkinUrl?: string | null;
}): string {
  return `<p>Hello ${escapeHtml(name)},</p><p>Your check-in sheet for <strong>${
    escapeHtml(showName)
  }</strong> is attached.${
    waveLabel ? ` This sheet is for ${escapeHtml(waveLabel)}.` : ""
  }</p>${waveLabel ? `<p>${waveSheetNote}</p>` : ""}${
    checkinUrl
      ? `<p><a href="${
        escapeHtml(checkinUrl)
      }">Open the check-in page</a></p><p>Use your exhibitor number and last name to check in during your scheduled check-in window.</p>`
      : ""
  }<p>Please review your entries and contact the show secretary if anything needs corrected.</p><p>Thank you,<br>RingMaster Show</p>`;
}
export function waveDeliveryKey(
  showId: string,
  exhibitorId: string,
  waveId: string | null,
  resendId: string | null = null,
): string {
  // Preserve the provider key for any legacy delivery already in progress.
  return `auto-checkin/${showId}/${exhibitorId}${waveId ? `/${waveId}` : ""}${
    resendId ? `/resend/${resendId}` : ""
  }`;
}

// A service-only receipt can be queued for an explicit resend with a fresh
// request ID. Persist the newly generated content before contacting Resend;
// retries then retain the same content and key, just like the original send.
export function prepareDeliveryAttempt(
  stored: Record<string, unknown>,
  generated: Record<string, unknown>,
) {
  const resendId = stored?._resend_id == null
    ? null
    : String(stored._resend_id);
  if (
    resendId &&
    !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
      resendId,
    )
  ) {
    throw new Error("Invalid resend request ID.");
  }
  const needsSave = Boolean(resendId) && Object.keys(stored).length === 1;
  const durable = needsSave ? { ...generated, _resend_id: resendId } : stored;
  if (
    !durable || !Array.isArray(durable.attachments) ||
    !durable.attachments.length
  ) {
    throw new Error("Saved check-in email payload is incomplete.");
  }
  const providerPayload = { ...durable };
  delete providerPayload._resend_id;
  return { resendId, needsSave, durable, providerPayload };
}
