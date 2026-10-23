// This module can only invoke the configured private report renderer. It never
// calls Cloud Scheduler or accepts a worker URL from the portal request.
export function createWorkerTrigger({
  workerUrl, workToken, getIdentityToken, waitUntil,
  request = fetch, onFailure = () => {}, timeoutMs = 120_000,
}: {
  workerUrl: string;
  workToken: string;
  getIdentityToken: (audience: string) => Promise<string>;
  waitUntil: (task: Promise<void>) => void;
  request?: typeof fetch;
  onFailure?: () => void;
  timeoutMs?: number;
}) {
  return async function triggerWorker(): Promise<void> {
    if (!/^https:\/\/[a-z0-9-]+(?:\.[a-z0-9-]+)?\.run\.app$/.test(workerUrl) || !workToken) {
      throw new Error('Report worker is not configured');
    }
    // Each committed request gets a wake-up: coalescing for the whole render
    // could miss work queued after an earlier dispatch's final queue claim.
    const task = (async () => {
      const controller = new AbortController();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const deadline = new Promise<never>((_, reject) => {
        timer = setTimeout(() => {
          controller.abort();
          reject(new Error('Report worker wake-up timed out'));
        }, timeoutMs);
      });
      try {
        await Promise.race([deadline, (async () => {
          const token = await getIdentityToken(workerUrl);
          controller.signal.throwIfAborted();
          const response = await request(`${workerUrl}/dispatch`, {
            method: 'POST', redirect: 'error', signal: controller.signal,
            headers: {Authorization: `Bearer ${token}`, 'X-Work-Token': workToken,
              'Content-Type': 'application/json'}, body: '{}',
          });
          if (!response.ok) throw new Error('Report worker rejected wake-up');
          await response.arrayBuffer();
        })()]);
      } finally {
        clearTimeout(timer);
      }
    })().catch(() => { onFailure(); });
    // /dispatch holds its response until rendering finishes. Keep its request
    // alive after the portal response using the supported Edge lifecycle API.
    // The database queue + cron remain the durable recovery path on shutdown.
    waitUntil(task);
  };
}
