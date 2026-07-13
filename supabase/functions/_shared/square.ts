export const squareScopes = [
  "MERCHANT_PROFILE_READ",
  "PAYMENTS_WRITE",
  "PAYMENTS_WRITE_ADDITIONAL_RECIPIENTS",
] as const;

export const requiredSquarePaymentScopes = [...squareScopes];

export function normalizeSquareScopes(value: unknown): string[] {
  let rawScopes: unknown[];
  if (Array.isArray(value)) {
    rawScopes = value;
  } else if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return [];
    if (trimmed.startsWith("[")) {
      try {
        return normalizeSquareScopes(JSON.parse(trimmed));
      } catch (_) {
        // Fall through to the documented string representation.
      }
    }
    rawScopes = trimmed.split(/[\s,]+/);
  } else {
    return [];
  }

  return [
    ...new Set(
      rawScopes
        .flatMap((scope) =>
          typeof scope === "string" ? scope.split(/[\s,]+/) : []
        )
        .map((scope) => scope.trim())
        .filter(Boolean),
    ),
  ];
}

export function squareAuthorizationWasRevoked(
  status: Record<string, unknown>,
): boolean {
  if (status.revoked === true) return true;
  return [status.status, status.authorization_status, status.revocation_status]
    .some((value) => String(value ?? "").toUpperCase() === "REVOKED");
}

export const squareEnvironment = (Deno.env.get("SQUARE_ENVIRONMENT") ?? "sandbox")
  .toLowerCase();
export const squareConnectBase = squareEnvironment === "production"
  ? "https://connect.squareup.com"
  : "https://connect.squareupsandbox.com";
export const squareApiVersion = Deno.env.get("SQUARE_API_VERSION")?.trim() ||
  "2026-05-20";

export function squareEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing Square server configuration: ${name}.`);
  return value;
}

async function squareJson(
  response: Response,
): Promise<Record<string, unknown>> {
  const data = await response.json().catch(() => ({})) as Record<
    string,
    unknown
  >;
  if (!response.ok) {
    const errors = Array.isArray(data.errors) ? data.errors : [];
    const detail = errors.length && typeof errors[0] === "object"
      ? String((errors[0] as Record<string, unknown>).detail ?? "")
      : "";
    throw new Error(detail || `Square request failed (${response.status}).`);
  }
  return data;
}

export class SquareRequestError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
  ) {
    super(message);
  }
}

export async function squareRequest(
  path: string,
  accessToken: string,
  init: RequestInit = {},
): Promise<Record<string, unknown>> {
  const response = await fetch(`${squareConnectBase}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      "Square-Version": squareApiVersion,
      ...(init.headers ?? {}),
    },
  });
  const data = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok) {
    const first = Array.isArray(data.errors) && data.errors[0] &&
        typeof data.errors[0] === "object"
      ? data.errors[0] as Record<string, unknown>
      : {};
    throw new SquareRequestError(
      String(first.detail ?? "Square could not process the payment."),
      response.status,
      String(first.code ?? "SQUARE_REQUEST_FAILED"),
    );
  }
  return data;
}

export async function obtainSquareToken(
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  return squareJson(
    await fetch(`${squareConnectBase}/oauth2/token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Square-Version": squareApiVersion,
      },
      body: JSON.stringify({
        client_id: squareEnv("SQUARE_APPLICATION_ID"),
        client_secret: squareEnv("SQUARE_APPLICATION_SECRET"),
        ...body,
      }),
    }),
  );
}

export async function squareGet(
  path: string,
  accessToken: string,
): Promise<Record<string, unknown>> {
  return squareJson(
    await fetch(`${squareConnectBase}${path}`, {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Square-Version": squareApiVersion,
      },
    }),
  );
}

export async function tokenStatus(
  accessToken: string,
): Promise<Record<string, unknown>> {
  return squareJson(
    await fetch(`${squareConnectBase}/oauth2/token/status`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "Square-Version": squareApiVersion,
      },
      body: "{}",
    }),
  );
}

export type PublicLocation = {
  id: string;
  name: string;
  status: string;
  merchantId?: string;
  currency?: string;
  address?: string;
};

export function usableLocations(
  data: Record<string, unknown>,
): PublicLocation[] {
  const locations = Array.isArray(data.locations) ? data.locations : [];
  return locations.flatMap((raw) => {
    if (!raw || typeof raw !== "object") return [];
    const location = raw as Record<string, unknown>;
    const id = String(location.id ?? "").trim();
    const status = String(location.status ?? "").trim();
    const capabilities = Array.isArray(location.capabilities)
      ? location.capabilities.map(String)
      : [];
    if (
      !id || status !== "ACTIVE" ||
      !capabilities.includes("CREDIT_CARD_PROCESSING")
    ) return [];
    const address = location.address && typeof location.address === "object"
      ? location.address as Record<string, unknown>
      : {};
    const addressText = [
      address.address_line_1,
      address.locality,
      address.administrative_district_level_1,
    ]
      .map((part) => String(part ?? "").trim()).filter(Boolean).join(", ");
    return [{
      id,
      name: String(location.name ?? "Square location"),
      status,
      merchantId: String(location.merchant_id ?? ""),
      currency: String(location.currency ?? "").toLowerCase(),
      ...(addressText ? { address: addressText } : {}),
    }];
  });
}

export function publicMerchant(
  data: Record<string, unknown>,
): Record<string, unknown> {
  const merchant = data.merchant && typeof data.merchant === "object"
    ? data.merchant as Record<string, unknown>
    : {};
  return {
    id: String(merchant.id ?? ""),
    business_name: String(merchant.business_name ?? ""),
    status: String(merchant.status ?? ""),
    country: String(merchant.country ?? ""),
    currency: String(merchant.currency ?? ""),
  };
}
