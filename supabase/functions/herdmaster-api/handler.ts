export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}
type RecordValue = Record<string, unknown>;
export interface Dependencies {
  user(request: Request): Promise<string>;
  connect(owner: string, externalAccount: string): Promise<RecordValue>;
  refresh(refreshToken: string): Promise<RecordValue>;
  revoke(owner: string, id: string): Promise<boolean>;
  rpc(name: string, args: RecordValue): Promise<unknown>;
  hash(token: string): Promise<string>;
  sign(bucket: string, path: string): Promise<string>;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const timestamp =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
};
function response(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers });
}
function invalid(message: string): never {
  throw new ApiError(422, "invalid_request", message);
}
function object(value: unknown): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    invalid("Expected a JSON object.");
  }
  return value as RecordValue;
}
function text(value: unknown, field: string, required = true): string | null {
  if (!required && (value === undefined || value === null)) return null;
  if (typeof value !== "string" || !value.trim() || value.length > 200) {
    invalid(`${field} must be a nonempty string of at most 200 characters.`);
  }
  return value.trim();
}
async function body(request: Request): Promise<RecordValue> {
  if (
    !request.headers.get("content-type")?.toLowerCase().startsWith(
      "application/json",
    )
  ) {
    throw new ApiError(415, "unsupported_media_type", "Use application/json.");
  }
  const reader = request.body?.getReader();
  if (!reader) invalid("A JSON body is required.");
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1048576) {
        await reader.cancel();
        throw new ApiError(
          413,
          "payload_too_large",
          "Maximum body size is 1 MiB.",
        );
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    return object(JSON.parse(new TextDecoder().decode(bytes)));
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError(400, "invalid_json", "Malformed JSON body.");
  } finally {
    reader.releaseLock();
  }
}
export function animals(value: unknown): RecordValue[] {
  if (!Array.isArray(value) || value.length > 500) {
    invalid("animals must contain at most 500 records.");
  }
  const ids = new Set<string>();
  return value.map((raw) => {
    const a = object(raw);
    const id = text(a.id, "id")!;
    if (ids.has(id)) invalid("Duplicate animal IDs in a batch.");
    ids.add(id);
    if (typeof a.active !== "boolean") invalid("active must be a boolean.");
    const updated = a.updated_at;
    if (
      typeof updated !== "string" || !timestamp.test(updated) ||
      !Number.isFinite(Date.parse(updated))
    ) invalid("updated_at must be an ISO 8601 timestamp with a time zone.");
    if (!a.active) return { id, active: false, updated_at: updated };
    if (a.species !== "rabbit" && a.species !== "cavy") {
      invalid("species must be rabbit or cavy.");
    }
    const sexes = a.species === "rabbit" ? ["Buck", "Doe"] : ["Boar", "Sow"];
    if (!sexes.includes(a.sex as string)) {
      invalid(`sex must be ${sexes.join(" or ")}.`);
    }
    const dob = a.dob ?? null;
    if (
      dob !== null &&
      (typeof dob !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dob) ||
        !Number.isFinite(Date.parse(dob)) ||
        new Date(dob).toISOString().slice(0, 10) !== dob)
    ) invalid("dob must be a valid YYYY-MM-DD date or null.");
    const existing = a.ringmaster_animal_id ?? null;
    if (
      existing !== null &&
      (typeof existing !== "string" || !uuid.test(existing))
    ) invalid("ringmaster_animal_id must be a UUID or null.");
    return {
      id,
      active: true,
      updated_at: updated,
      species: a.species,
      tattoo: text(a.tattoo, "tattoo"),
      breed: text(a.breed, "breed"),
      variety: text(a.variety, "variety", false),
      pattern: text(a.pattern, "pattern", false),
      sex: a.sex,
      dob,
      name: text(a.name, "name", false),
      ringmaster_animal_id: existing,
    };
  });
}
export function createHandler(deps: Dependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers });
    }
    try {
      const url = new URL(request.url);
      const root = url.pathname.indexOf("/herdmaster-api");
      const path = root < 0
        ? url.pathname
        : url.pathname.slice(root + "/herdmaster-api".length);
      if (path === "/v1/connections" && request.method === "POST") {
        const owner = await deps.user(request);
        const data = await body(request);
        if (data.consent !== true) {
          invalid(
            "Explicit consent=true is required for existing Show animal matching, animal updates, results, and exhibitor reports with HerdMaster.",
          );
        }
        return response(
          await deps.connect(
            owner,
            text(data.herdmaster_account_id, "herdmaster_account_id")!,
          ),
          201,
        );
      }
      if (path === "/v1/connections/refresh" && request.method === "POST") {
        const data = await body(request);
        const refreshToken = data.refresh_token;
        if (typeof refreshToken !== "string" ||
            !/^rmhmr_[A-Za-z0-9_-]{43}$/.test(refreshToken)) {
          throw new ApiError(401, "invalid_refresh_token",
            "A valid HerdMaster refresh token is required.");
        }
        return response(await deps.refresh(refreshToken));
      }
      if (path.startsWith("/v1/connections/") && request.method === "DELETE") {
        const owner = await deps.user(request);
        const id = path.slice("/v1/connections/".length);
        if (!uuid.test(id)) invalid("Connection ID must be a UUID.");
        if (!await deps.revoke(owner, id)) {
          throw new ApiError(404, "not_found", "Connection not found.");
        }
        return response({ revoked: true });
      }
      const route = path === "/v1/animals/existing"
        ? "existing"
        : path === "/v1/animals"
        ? "animals"
        : path === "/v1/results"
        ? "results"
        : path === "/v1/reports"
        ? "reports"
        : path === "/v1/catalog"
        ? "catalog"
        : null;
      if (!route) throw new ApiError(404, "not_found", "Unknown endpoint.");
      if (request.method !== (route === "animals" ? "POST" : "GET")) {
        throw new ApiError(405, "method_not_allowed", "Unsupported method.");
      }
      const token = request.headers.get("Authorization")?.match(
        /^Bearer (rmhm_[A-Za-z0-9_-]{43})$/,
      )?.[1];
      if (!token) {
        throw new ApiError(
          401,
          "unauthorized",
          "A HerdMaster connection token is required.",
        );
      }
      const hash = await deps.hash(token);
      if (route === "animals") {
        const data = await body(request);
        const records = animals(data.animals);
        if (data.refresh_request_id !== undefined || data.refresh_complete !== undefined) {
          if (typeof data.refresh_request_id !== "string" || !uuid.test(data.refresh_request_id) ||
              typeof data.refresh_complete !== "boolean") {
            invalid("Refresh batches require a UUID refresh_request_id and boolean refresh_complete.");
          }
          return response(await deps.rpc("animal_sync_apply_herdmaster", {
            p_hash: hash, p_animals: records,
            p_request: data.refresh_request_id, p_complete: data.refresh_complete,
          }));
        }
        return response(await deps.rpc("herdmaster_apply_animals", {
          p_hash: hash, p_animals: records,
        }));
      }
      const after = url.searchParams.get("after");
      if (after !== null && !uuid.test(after)) invalid("after must be a UUID.");
      if (route === "existing") return response(await deps.rpc("partner_existing_animals", {p_hash: hash, p_after: after}));
      const rows = await deps.rpc("herdmaster_export", {
        p_hash: hash,
        p_kind: route,
        p_after: after,
      }) as { id: string; payload: RecordValue }[];
      const data = await Promise.all(rows.map(async ({ payload }) => {
        if (route !== "reports") return payload;
        const { storage_bucket, storage_path, ...report } = payload;
        return {
          ...report,
          download_url: await deps.sign(
            String(storage_bucket),
            String(storage_path),
          ),
          download_expires_in: 300,
        };
      }));
      return response({
        data,
        next_after: rows.length === 500 ? rows.at(-1)!.id : null,
        sync_mode: "full_scan",
      });
    } catch (error) {
      if (error instanceof ApiError) {
        return response(
          { error: { code: error.code, message: error.message } },
          error.status,
        );
      }
      // Never disclose database, upstream, token, or user details.
      return response({
        error: {
          code: "temporarily_unavailable",
          message: "The integration is temporarily unavailable. Retry later.",
        },
      }, 503);
    }
  };
}
