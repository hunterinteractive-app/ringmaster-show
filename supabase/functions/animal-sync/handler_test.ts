import { createSyncHandler, Link, SyncError, loadBreederStatus } from './handler.ts';
const owner = '00000000-0000-4000-8000-000000000001';
const link: Link = { key: 'test:1', provider: 'test', name: 'Test', connection_id: owner, can_refresh: true, last_refreshed_at: null, external_account_id: 'private-account' };
const assert = (ok: unknown) => { if (!ok) throw new Error('Assertion failed'); };
const request = (action: string, extra = {}) => new Request('https://example.invalid/animal-sync', { method: 'POST', body: JSON.stringify({ owner_id: owner, action, ...extra }) });
Deno.test('status reads never refresh animals or expose external account identifiers', async () => {
  const handle = createSyncHandler({ authorize: async () => {}, links: async () => ({ providers: [link] }), refresh: () => { throw new Error('Must not refresh'); } });
  const response = await handle(request('status'));
  assert(response.status === 200);
  const data = await response.json();
  assert(data.providers.length === 1 && !('external_account_id' in data.providers[0]));
});
Deno.test('cross-household requests stop before reading links', async () => {
  const handle = createSyncHandler({ authorize: () => { throw new SyncError(403, 'Denied'); }, links: () => { throw new Error('Must not read'); }, refresh: async () => {} });
  assert((await handle(request('refresh', { provider_key: link.key }))).status === 403);
});
Deno.test('unlinked and unavailable providers cannot be refreshed', async () => {
  const handle = createSyncHandler({ authorize: async () => {}, links: async () => ({ providers: [{ ...link, can_refresh: false }] }), refresh: () => { throw new Error('Must not refresh'); } });
  assert((await handle(request('refresh', { provider_key: 'unknown' }))).status === 404);
  assert((await handle(request('refresh', { provider_key: link.key }))).status === 409);
});
Deno.test('failed delivery is not reported as a successful refresh', async () => {
  const handle = createSyncHandler({ authorize: async () => {}, links: async () => ({ providers: [link] }), refresh: () => { throw new Error('Delivery incomplete'); } });
  const response = await handle(request('refresh', { provider_key: link.key }));
  assert(response.status === 503 && !(await response.json()).refreshed);
});
Deno.test('only completed delivery reports refreshed', async () => {
  let delivered = false;
  const handle = createSyncHandler({ authorize: async () => {}, links: async () => ({ providers: [link] }), refresh: async () => { delivered = true; } });
  const response = await handle(request('refresh', { provider_key: link.key }));
  assert(delivered && response.status === 200 && (await response.json()).refreshed === true);
});
Deno.test('HerdMaster refresh never calls the Breeder status service', async () => {
  let calls = 0;
  const lookup = () => { calls++; return Promise.resolve({ connected: true }); };
  assert(await loadBreederStatus(`herdmaster:${owner}`, lookup) === null);
  assert(calls === 0);
  assert((await loadBreederStatus(`ringmaster_breeder:${owner}`, lookup))?.connected);
  assert(calls === 1);
  assert((await loadBreederStatus(undefined, lookup))?.connected);
  assert(Number(calls) === 2);
});
Deno.test('handler scopes refresh lookup while preserving complete status discovery', async () => {
  const scopes: (string | undefined)[] = [];
  const handle = createSyncHandler({
    authorize: async () => {},
    links: async (_owner, _request, key) => { scopes.push(key); return { providers: [link] }; },
    refresh: async () => {},
  });
  assert((await handle(request('refresh', { provider_key: link.key }))).status === 200);
  assert((await handle(request('status'))).status === 200);
  assert(scopes[0] === link.key && scopes[1] === undefined);
});
