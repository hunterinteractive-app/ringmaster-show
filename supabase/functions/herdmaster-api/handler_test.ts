import {
  animals,
  ApiError,
  createHandler,
  type Dependencies,
} from "./handler.ts";

function assert(
  condition: unknown,
  message = "Assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}
const animal = {
  id: "HM-1",
  active: true,
  updated_at: "2026-10-12T14:00:00Z",
  species: "rabbit",
  sex: "Buck",
  tattoo: "A1",
  breed: "Mini Rex",
  dob: null,
};
const token = `rmhm_${"a".repeat(43)}`;
const entry = "12345678-1234-1234-1234-123456789abc";
function setup(overrides: Partial<Dependencies> = {}) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const deps: Dependencies = {
    user: () => Promise.resolve("owner"),
    connect: () => Promise.resolve({ connection_id: entry, token }),
    refresh: () => Promise.resolve({ connection_id: entry, token }),
    revoke: () => Promise.resolve(true),
    rpc: (name, args) => {
      calls.push({ name, args });
      return Promise.resolve(
        name === "herdmaster_apply_animals" ? { applied: 1, ignored: 0 } : [],
      );
    },
    hash: () => Promise.resolve("hash"),
    sign: () => Promise.resolve("https://example.invalid/report"),
    ...overrides,
  };
  return { handle: createHandler(deps), calls };
}
function req(path: string, method = "GET", payload?: unknown, bearer = token) {
  return new Request(
    `https://example.invalid/functions/v1/herdmaster-api/v1/${path}`,
    {
      method,
      headers: {
        Authorization: `Bearer ${bearer}`,
        "Content-Type": "application/json",
      },
      body: payload === undefined ? undefined : JSON.stringify(payload),
    },
  );
}
Deno.test("refresh delivery binds a validated request ID and completion flag", async () => {
  const { handle, calls } = setup();
  const response = await handle(req('animals', 'POST', {
    animals: [animal], refresh_request_id: entry, refresh_complete: true,
  }));
  assert(response.status === 200);
  assert(calls[0].name === 'animal_sync_apply_herdmaster');
  assert(calls[0].args.p_request === entry && calls[0].args.p_complete === true);
});
Deno.test("incomplete refresh delivery metadata is rejected before any write", async () => {
  const { handle, calls } = setup();
  assert((await handle(req('animals', 'POST', { animals: [], refresh_complete: true }))).status === 422);
  assert((await handle(req('animals', 'POST', { animals: [], refresh_request_id: entry }))).status === 422);
  assert(calls.length === 0);
});
Deno.test("partner cannot create a connection with its token", async () => {
  const { handle } = setup({
    user: () => {
      throw new ApiError(401, "unauthorized", "User required");
    },
  });
  assert(
    (await handle(
      req("connections", "POST", {
        consent: true,
        herdmaster_account_id: "HM",
      }),
    )).status === 401,
  );
});
Deno.test("connection creation requires explicit consent", async () => {
  const { handle } = setup();
  assert(
    (await handle(
      req("connections", "POST", { herdmaster_account_id: "HM" }, "user-jwt"),
    )).status === 422,
  );
  assert(
    (await handle(
      req(
        "connections",
        "POST",
        { consent: true, herdmaster_account_id: "HM" },
        "user-jwt",
      ),
    )).status === 201,
  );
});
Deno.test("JWT cannot access partner data endpoints", async () => {
  const { handle, calls } = setup();
  assert(
    (await handle(req("results", "GET", undefined, "user-jwt"))).status === 401,
  );
  assert(calls.length === 0);
});
Deno.test("animal batch normalizes optional fields and binds only token hash", async () => {
  const { handle, calls } = setup();
  const response = await handle(
    req("animals", "POST", { owner_id: "attacker", animals: [animal] }),
  );
  assert(response.status === 200);
  assert(calls[0].args.p_hash === "hash" && !("owner_id" in calls[0].args));
  const normalized = (calls[0].args.p_animals as Record<string, unknown>[])[0];
  assert(normalized.dob === null && normalized.variety === null);
});
Deno.test("invalid dates, timestamp zones, sex, duplicate IDs, and large batches are rejected", () => {
  for (
    const batch of [
      [{ ...animal, dob: "2026-02-30" }],
      [{ ...animal, updated_at: "2026-10-12T14:00:00" }],
      [{ ...animal, sex: "Boar" }],
      [animal, animal],
      Array.from({ length: 501 }, (_, i) => ({ ...animal, id: String(i) })),
    ]
  ) {
    let failed = false;
    try {
      animals(batch);
    } catch (error) {
      failed = error instanceof ApiError && error.status === 422;
    }
    assert(failed);
  }
});
Deno.test("inactive updates need no breed or birth date", () => {
  assert(
    animals([{ id: "HM-1", active: false, updated_at: animal.updated_at }])
      .length === 1,
  );
});
Deno.test("invalid cursor never reaches database", async () => {
  const { handle, calls } = setup();
  assert((await handle(req("results?after=bad"))).status === 422);
  assert(calls.length === 0);
});
Deno.test("full result page returns a next cursor and preserves result fields", async () => {
  const rows = Array.from(
    { length: 500 },
    () => ({ id: entry, payload: { entry_id: entry, placement: 1 } }),
  );
  const { handle } = setup({ rpc: () => Promise.resolve(rows) });
  const data = await (await handle(req("results"))).json();
  assert(
    data.next_after === entry && data.data.length === 500 &&
      data.sync_mode === "full_scan",
  );
});
Deno.test("report storage paths are replaced by expiring download URLs", async () => {
  const { handle } = setup({
    rpc: () =>
      Promise.resolve([{
        id: entry,
        payload: {
          report_id: entry,
          storage_bucket: "private",
          storage_path: "private.pdf",
        },
      }]),
  });
  const result = await (await handle(req("reports"))).json();
  assert(
    result.data[0].download_expires_in === 300 && result.data[0].download_url,
  );
  assert(
    !("storage_path" in result.data[0]) &&
      !("storage_bucket" in result.data[0]),
  );
});
Deno.test("revoked credentials are rejected and internal errors are redacted", async () => {
  const { handle } = setup({
    rpc: () => {
      throw new ApiError(401, "unauthorized", "Revoked");
    },
  });
  assert((await handle(req("results"))).status === 401);
  const { handle: unavailable } = setup({
    rpc: () => {
      throw new Error("SECRET_DATABASE_TOKEN");
    },
  });
  const result = await unavailable(req("results"));
  assert(result.status === 503 && !(await result.text()).includes("SECRET"));
});
Deno.test("malformed JSON and oversized body are rejected", async () => {
  const { handle } = setup();
  const malformed = req("animals", "POST");
  const bad = new Request(malformed, { body: "{" });
  assert((await handle(bad)).status === 400);
  assert(
    (await handle(
      req("animals", "POST", { animals: [], filler: "a".repeat(1048576) }),
    )).status === 413,
  );
});
Deno.test("revocation hides other users connections", async () => {
  const { handle } = setup({ revoke: () => Promise.resolve(false) });
  assert(
    (await handle(req(`connections/${entry}`, "DELETE", undefined, "jwt")))
      .status === 404,
  );
});

Deno.test("existing animal listing uses only the credential hash and validated cursor", async () => {
 const calls: unknown[]=[];
 const {handle}=setup({rpc:(name,args)=>{calls.push({name,args});return Promise.resolve({data:[],next_after:null});}});
 const result=await handle(req('animals/existing','GET',undefined,token));
 assert(result.status===200);
 assert(JSON.stringify(calls).includes('partner_existing_animals'));
 assert(!JSON.stringify(calls).includes(token));
});
