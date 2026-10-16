import { createClient } from 'npm:@supabase/supabase-js@2.95.0';
import { createSyncHandler, Link, SyncError, loadBreederStatus } from './handler.ts';

const env = (name: string) => Deno.env.get(name)?.trim() ?? '';
const admin = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'), {
  auth: { persistSession: false, autoRefreshToken: false },
});
const breederUrl = 'https://aqfsrolvaewcpkdkttiz.supabase.co/functions/v1/show-connection';
const fetchJson = async (url: string, headers: Record<string, string>, body: unknown) => {
  const response = await fetch(url, {
    method: 'POST', redirect: 'error',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify(body), signal: AbortSignal.timeout(45_000),
  });
  if (!response.ok) throw new SyncError(response.status === 409 ? 409 : 503, 'Provider refresh could not complete. Please retry.');
  return await response.json();
};
const breeder = (request: Request, body: unknown) => fetchJson(breederUrl,
  { Authorization: request.headers.get('Authorization') ?? '' }, body);
const callbackReady = () => {
  try { return new URL(env('HERDMASTER_ANIMAL_SYNC_URL')).protocol === 'https:' && !!env('HERDMASTER_ANIMAL_SYNC_SECRET'); }
  catch { return false; }
};
async function mark(owner: string, link: Link, at: string) {
  const { error } = await admin.from('animal_sync_state').upsert({
    owner_user_id: owner, provider: link.provider, connection_id: link.connection_id,
    last_refreshed_at: at,
  }, { onConflict: 'provider,connection_id' });
  if (error) throw error;
}

// Add new provider adapters here; the Flutter panel consumes generic Link records.
Deno.serve(createSyncHandler({
  async authorize(request, owner) {
    const token = (request.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data.user?.email_confirmed_at) throw new SyncError(401, 'Sign in again to refresh animals.');
    if (data.user.id !== owner) {
      const scoped = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
        global: { headers: { Authorization: `Bearer ${token}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const access = await scoped.rpc('household_access', { p_action: 'list' });
      if (access.error || !access.data?.households?.some((h: { owner_user_id: string }) => h.owner_user_id === owner)) {
        throw new SyncError(403, 'Household access denied.');
      }
    }
  },
  async links(owner, request, providerKey) {
    const [connections, states, source] = await Promise.all([
      admin.from('herdmaster_connections').select('id,external_account_id,expires_at,refresh_expires_at').eq('owner_user_id', owner).eq('provider','herdmaster').is('revoked_at', null),
      admin.from('animal_sync_state').select('provider,connection_id,last_refreshed_at').eq('owner_user_id', owner),
      loadBreederStatus(providerKey, () => breeder(request, { action: 'show_status', owner_id: owner }))
        .then(data => ({ data, error: null })).catch(() => ({ data: null, error: true })),
    ]);
    if (connections.error || states.error) throw new Error('Account status unavailable');
    const last = (provider: string, connection: string) => states.data.find(s => s.provider === provider && s.connection_id === connection)?.last_refreshed_at ?? null;
    const providers: Link[] = [];
    if (source.data?.connected) {
      providers.push({ key: `ringmaster_breeder:${source.data.connection_id}`, name: 'RingMaster Breeder', provider: 'ringmaster_breeder',
        connection_id: source.data.connection_id, can_refresh: true,
        last_refreshed_at: source.data.last_refreshed_at ?? last('ringmaster_breeder', source.data.connection_id) });
    }
    for (const c of connections.data) {
      const active = Date.parse(c.refresh_expires_at ?? c.expires_at) > Date.now();
      providers.push({ key: `herdmaster:${c.id}`, name: 'HerdMaster', provider: 'herdmaster', connection_id: c.id,
        external_account_id: c.external_account_id, can_refresh: active && callbackReady(),
        last_refreshed_at: last('herdmaster', c.id),
        ...(!active ? { unavailable_reason: 'Reconnect your account' } : !callbackReady() ? { unavailable_reason: 'Refresh integration pending' } : {}) });
    }
    return { providers, ...(source.error ? { status_warning: 'RingMaster Breeder account status is temporarily unavailable.' } : {}) };
  },
  async refresh(link, owner, request) {
    const started = await admin.rpc('animal_sync_begin', { p_owner: owner, p_provider: link.provider, p_connection: link.connection_id });
    if (started.error) throw new SyncError(started.error.code === '55P03' ? 409 : 503, 'A refresh is in progress or unavailable. Please retry shortly.');
    const id = started.data;
    try {
      if (link.provider === 'ringmaster_breeder') {
        const result = await breeder(request, { action: 'pull', owner_id: owner });
        if (result.connected !== true || !result.last_refreshed_at || result.connection_id !== link.connection_id) throw new Error('Account disconnected during refresh');
        await mark(owner, link, result.last_refreshed_at);
        const saved = await admin.from('animal_sync_requests').update({ status: 'completed', completed_at: result.last_refreshed_at }).eq('id', id).eq('status', 'pending');
        if (saved.error) throw saved.error;
      } else if (link.provider === 'herdmaster') {
        await fetchJson(env('HERDMASTER_ANIMAL_SYNC_URL'), { Authorization: `Bearer ${env('HERDMASTER_ANIMAL_SYNC_SECRET')}` }, {
          request_id: id, connection_id: link.connection_id, herdmaster_account_id: link.external_account_id,
        });
        // A provider HTTP 200 alone is not proof that animals were delivered.
        const completed = await admin.from('animal_sync_requests').select('status').eq('id', id).single();
        if (completed.error || completed.data.status !== 'completed') throw new Error('Provider has not completed the animal snapshot');
      } else { throw new Error('Provider adapter unavailable'); }
    } catch (error) {
      // Only pending work is failed; a committed final animal batch remains successful.
      const completed = await admin.from('animal_sync_requests').select('status').eq('id', id).single();
      if (!completed.error && completed.data.status === 'completed') return;
      await admin.from('animal_sync_requests').update({ status: 'failed' }).eq('id', id).eq('status', 'pending');
      throw error;
    }
  },
}));
