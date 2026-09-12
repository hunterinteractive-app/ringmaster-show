/** Bound stalled upstream requests and expose timing without logging tokens,
 * URLs, request bodies, email addresses, or other personal data. */
export class UpstreamUnavailable extends Error {
  constructor() {
    super("The service is temporarily busy. Please try again.");
  }
}

/** Share one deadline across all upstream stages of an account lookup. */
export function budgetedFetch(
  label: string,
  deadline: AbortSignal,
  fetcher: typeof fetch = fetch,
): typeof fetch {
  const observed = observedFetch(label, fetcher);
  return async (input, init) => {
    const request = new Request(input, init);
    try {
      deadline.throwIfAborted();
      return await observed(
        new Request(request, {
          signal: AbortSignal.any([request.signal, deadline]),
        }),
      );
    } catch (error) {
      if (deadline.aborted) throw new UpstreamUnavailable();
      throw error;
    }
  };
}

export function observedFetch(
  label: string,
  fetcher: typeof fetch = fetch,
  timeoutMs = 15_000,
): typeof fetch {
  return async (input, init) => {
    const request = new Request(input, init);
    const safeToRetry = request.method === "GET" || request.method === "HEAD" ||
      request.headers.has("Idempotency-Key");
    const attempts = safeToRetry ? 3 : 1;
    for (let attempt = 1; attempt <= attempts; attempt++) {
      const started = performance.now();
      let status: number | null = null;
      try {
        const response = await fetcher(request.clone(), {
          signal: AbortSignal.any([
            request.signal,
            AbortSignal.timeout(timeoutMs),
          ]),
        });
        status = response.status;
        if ([500, 502, 503, 504].includes(status) && attempt < attempts) {
          await response.body?.cancel();
        } else {
          return response;
        }
      } catch (error) {
        if (request.signal.aborted) throw error;
        if (attempt >= attempts) throw new UpstreamUnavailable();
      } finally {
        console.log(JSON.stringify({
          event: "upstream_request",
          operation: label,
          attempt,
          status,
          duration_ms: Math.round(performance.now() - started),
        }));
      }
      await new Promise((resolve) =>
        setTimeout(resolve, 250 * 2 ** (attempt - 1) + Math.random() * 250)
      );
    }
    throw new UpstreamUnavailable();
  };
}

/** A backend outage is not an invalid login. Callers must preserve that
 * distinction instead of converting all Auth errors to HTTP 401. */
export function authErrorStatus(error: { status?: number } | null): number {
  return error?.status && error.status >= 500 ? 503 : 401;
}
