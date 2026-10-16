export type Link = {
  key: string; name: string; provider: string; connection_id: string;
  can_refresh: boolean; last_refreshed_at: string | null;
  unavailable_reason?: string; external_account_id?: string;
};
export class SyncError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
export interface SyncDependencies {
  authorize(request: Request, owner: string): Promise<void>;
  links(owner: string, request: Request, providerKey?: string): Promise<{ providers: Link[]; status_warning?: string }>;
  refresh(link: Link, owner: string, request: Request): Promise<void>;
}
// Full status discovery checks Breeder. A targeted refresh checks only its provider.
export async function loadBreederStatus<T>(providerKey: string | undefined, lookup: () => Promise<T>): Promise<T | null> {
  return providerKey === undefined || providerKey.startsWith('ringmaster_breeder:') ? await lookup() : null;
}
const headers = {
  'Content-Type': 'application/json', 'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function createSyncHandler(deps: SyncDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
    try {
      const text = await request.text();
      if (text.length > 4096) return reply({ error: 'Request too large' }, 413);
      let body;
      try { body = JSON.parse(text); } catch { return reply({ error: 'Invalid JSON' }, 400); }
      if (!body || typeof body !== 'object' || !uuid.test(body.owner_id ?? '') ||
          !['status', 'refresh'].includes(body.action)) return reply({ error: 'Invalid request' }, 422);
      if (body.action === 'refresh' && (typeof body.provider_key !== 'string' ||
          !body.provider_key || body.provider_key.length > 200)) return reply({ error: 'Invalid provider key' }, 422);
      await deps.authorize(request, body.owner_id);
      const result = await deps.links(body.owner_id, request, body.action === 'refresh' ? body.provider_key : undefined);
      if (body.action === 'status') {
        // Never expose account IDs, callback URLs, or credentials to the client.
        return reply({ ...result, providers: result.providers.map(({ external_account_id: _, ...p }) => p) });
      }
      const link = result.providers.find(p => p.key === body.provider_key);
      if (!link) return reply({ error: 'Linked account not found' }, 404);
      if (!link.can_refresh) return reply({ error: 'Provider refresh is not available yet' }, 409);
      await deps.refresh(link, body.owner_id, request);
      return reply({ refreshed: true });
    } catch (error) {
      if (error instanceof SyncError) return reply({ error: error.message }, error.status);
      return reply({ error: 'Animal refresh is temporarily unavailable. Saved animals remain available.' }, 503);
    }
  };
}
