import { partnerHandler } from "./partner.ts";
const token = `rmhm_${"a".repeat(43)}`;
for (const provider of ["herdmaster", "pedigreehq"] as const) {
  Deno.test(`${provider} route rejects another provider's access and refresh credentials`, async () => {
    const queried: unknown[] = [];
    let rpc = false;
    const query = {
      select() {
        return this;
      },
      eq(k: string, v: unknown) {
        queried.push([k, v]);
        return this;
      },
      maybeSingle() {
        return Promise.resolve({ data: null, error: null });
      },
    };
    const fake = {
      from: () => query,
      rpc: () => {
        rpc = true;
        return Promise.resolve({ data: [], error: null });
      },
    };
    const handler = partnerHandler(provider, fake as never);
    const result = await handler(
      new Request("https://example.invalid/herdmaster-api/v1/results", {
        headers: { Authorization: `Bearer ${token}` },
      }),
    );
    if (
      result.status !== 401 || rpc ||
      !queried.some((x) =>
        JSON.stringify(x) === JSON.stringify(["provider", provider])
      )
    ) throw Error("Cross-provider access accepted");
    queried.length = 0;
    const refresh = await handler(
      new Request(
        "https://example.invalid/herdmaster-api/v1/connections/refresh",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refresh_token: `rmhmr_${"a".repeat(43)}` }),
        },
      ),
    );
    if (
      refresh.status !== 401 || rpc ||
      !queried.some((x) =>
        JSON.stringify(x) === JSON.stringify(["provider", provider])
      )
    ) throw Error("Cross-provider refresh accepted");
  });
}
