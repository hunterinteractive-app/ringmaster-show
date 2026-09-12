import { serviceClient } from "./supabase.ts";
import {
  isUpstreamUnavailable,
  authErrorStatus,
  throwDatabaseError,
  UpstreamUnavailable,
} from "./request_fetch.ts";

function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("database SDK preserves a retryable transport failure without replaying a write", async () => {
  const previousFetch = globalThis.fetch;
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  let calls = 0;
  try {
    Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
    Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "local-test-key");
    globalThis.fetch = (() => {
      calls++;
      throw new TypeError("Connection closed after sending the request");
    }) as typeof fetch;
    const result = await serviceClient().rpc("transport_probe", { value: 1 });
    assert(calls === 1, `Ambiguous write was sent ${calls} times`);
    assert(result.error && result.status === 0);
    assert(isUpstreamUnavailable(result.error));
    try {
      throwDatabaseError(result.error);
    } catch (error) {
      assert(error instanceof UpstreamUnavailable);
    }
  } finally {
    globalThis.fetch = previousFetch;
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousKey === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", previousKey);
  }
});

Deno.test("serialized transport recognition does not turn database rejections into retries", () => {
  for (const error of [
    { code: "42501", message: new UpstreamUnavailable().toString() },
    { code: "23505", message: "duplicate key" },
    { code: "", message: "Error: unrelated validation failure" },
    null,
  ]) {
    assert(!isUpstreamUnavailable(error));
  }
});

Deno.test("the Auth SDK's zero-status transport error remains a service outage", async () => {
  const { createClient } = await import("npm:@supabase/supabase-js@2");
  const client = createClient("http://127.0.0.1:54321", "local-test-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: () => Promise.reject(new UpstreamUnavailable()),
    },
  });
  const { error } = await client.auth.getUser("local-test-token");
  assert(error?.name === "AuthRetryableFetchError" && error.status === 0);
  assert(authErrorStatus(error) === 503);
  assert(authErrorStatus({ name: "AuthApiError", status: 401 }) === 401);
});
