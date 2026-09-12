import {
  authErrorStatus,
  budgetedFetch,
  observedFetch,
  UpstreamUnavailable,
} from "./request_fetch.ts";
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
Deno.test("retries a provider request with its original idempotency key and body", async () => {
  const attempts: { key: string | null; body: string }[] = [];
  const fake = (async (input: RequestInfo | URL) => {
    const req = input as Request;
    attempts.push({
      key: req.headers.get("Idempotency-Key"),
      body: await req.text(),
    });
    return new Response("{}", { status: attempts.length < 2 ? 503 : 200 });
  }) as typeof fetch;
  const result = await observedFetch("test", fake)("https://provider.invalid", {
    method: "POST",
    headers: { "Idempotency-Key": "same-attempt" },
    body: "same-payload",
  });
  assert(result.ok && attempts.length === 2);
  assert(
    attempts.every((a) =>
      a.key === "same-attempt" && a.body === "same-payload"
    ),
  );
});
Deno.test("never retries an arbitrary database write", async () => {
  let calls = 0;
  const fake = (async () => {
    calls++;
    return new Response("{}", { status: 503 });
  }) as typeof fetch;
  const response = await observedFetch("test", fake)(
    "https://database.invalid",
    { method: "POST", body: "{}" },
  );
  assert(response.status === 503 && calls === 1);
});
Deno.test("does not retry authorization failures or rate limits", async () => {
  for (const status of [400, 401, 403, 429]) {
    let calls = 0;
    const fake = (async () => {
      calls++;
      return new Response("{}", { status });
    }) as typeof fetch;
    assert(
      (await observedFetch("test", fake)("https://provider.invalid")).status ===
        status,
    );
    assert(calls === 1);
  }
});
Deno.test("aborts an upstream stall with a bounded number of attempts", async () => {
  let calls = 0;
  const fake =
    ((_input: RequestInfo | URL, init?: RequestInit) =>
      new Promise((_resolve, reject) => {
        calls++;
        init!.signal!.addEventListener(
          "abort",
          () => reject(init!.signal!.reason),
          { once: true },
        );
      })) as typeof fetch;
  try {
    await observedFetch("test", fake, 5)("https://provider.invalid");
    throw new Error("Expected failure");
  } catch (error) {
    assert(error instanceof UpstreamUnavailable);
  }
  assert(calls === 3);
});
Deno.test("Auth outages remain retryable 503s; invalid credentials remain 401s", () => {
  assert(authErrorStatus({ status: 500 }) === 503);
  assert(authErrorStatus({ status: 503 }) === 503);
  assert(authErrorStatus({ status: 401 }) === 401);
});

Deno.test("one deadline bounds every account lookup stage without retrying a timed out write", async () => {
  const controller = new AbortController();
  let calls = 0;
  const fake = ((_input: RequestInfo | URL, init?: RequestInit) => {
    calls++;
    return new Promise<Response>((_resolve, reject) => {
      init!.signal!.addEventListener(
        "abort",
        () => reject(init!.signal!.reason),
        { once: true },
      );
      controller.abort();
    });
  }) as typeof fetch;
  for (const method of ["POST", "GET"]) {
    try {
      await budgetedFetch("account_test", controller.signal, fake)(
        "https://upstream.invalid",
        { method },
      );
      throw new Error("Expected unavailable");
    } catch (error) {
      assert(error instanceof UpstreamUnavailable);
    }
  }
  assert(
    calls === 1,
    "Later stages must not restart an expired request budget",
  );
});
