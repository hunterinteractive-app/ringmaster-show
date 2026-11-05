// Forward only the application's data plane. Never forward a browser's
// Authorization, API key, arbitrary Host, redirect, or authentication request.
const functions = new Set([
  "animal-sync",
  "checkin-send-receipt",
  "claim-or-import-exhibitor",
  "convention-sale-checkout",
  "export-locked-show-data",
  "herdmaster-api",
  "household-send-invitation",
  "payment-quote-preview",
  "pedigreehq-api",
  "refund-show-entries",
  "run-closeout",
  "send-checkin-sheet-email",
  "send-club-report-batch",
  "send-exhibitor-report-email",
  "send-report-email",
  "show-assistant",
  "square-connect-select-location",
  "square-connect-start",
  "square-connect-status",
  "square-create-payment",
  "square-disconnect",
  "square-payment-attempt-status",
  "stripe-connect-account-status",
  "stripe-connect-create-login-link",
  "stripe-create-checkout-session",
  "stripe-connect-create-account-index-ts",
  "stripe-connect-create-account-link-index-ts",
]);
export function route(path: string): string | null {
  if (!path.startsWith("/") || path.includes("//") || path.includes("\\")) {
    return null;
  }
  let decoded: string;
  try {
    decoded = decodeURIComponent(path);
  } catch {
    return null;
  }
  if (
    decoded.includes("%") || decoded.includes("\\") || decoded.includes("//") ||
    decoded.split("/").some((s) => s === ".." || s === ".") ||
    /[\x00-\x1f?#]/.test(decoded)
  ) return null;
  if (decoded === "/partner/v1/breeder-refresh") {
    return "partner/breeder-refresh";
  }
  const parts = decoded.split("/");
  if (parts[2] !== "v1" || !parts[3]) return null;
  if (parts[1] === "rest" && /^[a-z_][a-z0-9_]*$/i.test(parts[3])) {
    if (parts[3] === "rpc") {
      return parts.length === 5 && /^[a-z_][a-z0-9_]*$/i.test(parts[4]) &&
          parts[4] !== "manage_support_session"
        ? "rpc/" + parts[4]
        : null;
    }
    return parts.length === 4 ? "table/" + parts[3] : null;
  }
  if (parts[1] === "storage" && parts[3] === "object") return "storage/object";
  if (parts[1] === "functions" && functions.has(parts[3])) {
    return "function/" + parts[3];
  }
  return null;
}
export const forwardHeaders = [
  "accept",
  "accept-profile",
  "content-profile",
  "content-type",
  "prefer",
  "range",
  "range-unit",
  "x-upsert",
  "cache-control",
  "if-match",
  "if-none-match",
];
export const responseHeaders = [
  "content-type",
  "content-disposition",
  "content-range",
  "range-unit",
  "etag",
  "preference-applied",
];
