import { assertEquals } from "jsr:@std/assert@1";
import {
  censusLocality,
  lookupConventionLocality,
} from "./convention_locality.ts";

Deno.test("Census response retains only city/state, not echoed point or boundaries", () => {
  assertEquals(
    censusLocality({
      result: {
        input: { x: -119.7911, y: 39.4861 },
        geographies: {
          States: [{ STUSAB: "NV", CENTLAT: "39.3", NAME: "Nevada" }],
          "Incorporated Places": [{ BASENAME: "Reno", NAME: "Reno city" }],
        },
      },
    }),
    { city: "Reno", state: "NV", status: "resolved" },
  );
});
Deno.test("unincorporated communities use Census designated places", () => {
  assertEquals(
    censusLocality({
      result: {
        geographies: {
          States: [{ STUSAB: "NV" }],
          "Census Designated Places": [{ BASENAME: "Sun Valley" }],
        },
      },
    }),
    { city: "Sun Valley", state: "NV", status: "resolved" },
  );
});
Deno.test("missing city is preserved honestly as state only", () => {
  assertEquals(
    censusLocality({
      result: {
        geographies: {
          States: [{ STUSAB: "NV" }],
        },
      },
    }),
    { city: null, state: "NV", status: "state_only" },
  );
});
Deno.test("missing, unsupported, and malformed results do not invent a locality", () => {
  for (
    const payload of [null, {}, {
      result: { geographies: { States: [{ STUSAB: "invalid" }] } },
    }]
  ) {
    assertEquals(censusLocality(payload), {
      city: null,
      state: null,
      status: "unavailable",
    });
  }
});
Deno.test("lookup sends no account data and rejects provider failures without logging", async () => {
  let calls = 0;
  const fake = ((input: URL | RequestInfo, init?: RequestInit) => {
    const url = new URL(String(input));
    assertEquals(url.hostname, "geocoding.geo.census.gov");
    assertEquals(url.searchParams.get("x"), "-119.7911");
    assertEquals(url.searchParams.get("y"), "39.4861");
    assertEquals(init?.body, undefined);
    assertEquals(new Headers(init?.headers).has("Authorization"), false);
    calls++;
    return Promise.resolve(new Response("unavailable", { status: 503 }));
  }) as typeof fetch;
  assertEquals(await lookupConventionLocality(39.4861, -119.7911, fake), {
    city: null,
    state: null,
    status: "unavailable",
  });
  assertEquals(calls, 1);
  const timeout = (() => Promise.reject(new Error("Timeout"))) as typeof fetch;
  assertEquals(await lookupConventionLocality(0, 0, timeout), {
    city: null,
    state: null,
    status: "unavailable",
  });
});
