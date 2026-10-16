import { importCandidates } from "./import_source.ts";
const assert = (value: unknown) => {
  if (!value) throw Error("Assertion failed");
};
const owner = {
  id: "owner",
  email: "verified@example.invalid",
  email_confirmed_at: "2026-01-01",
};
const row = {
  id: "profile",
  profile: {
    owner_user_id: "owner",
    email: "editable@example.invalid",
    type: "family",
    first_name: "Test",
  },
};
Deno.test("Club matches retain priority and never contact Breeder", async () => {
  const club = [{ id: "club" }];
  const result = await importCandidates(club, owner.email, () => {
    throw Error("Should not call");
  }, () => {
    throw Error("Should not call");
  });
  assert(result.matches === club && result.source === "ringmaster_club");
});
Deno.test("Breeder fallback binds the profile to verified source Auth and records provenance", async () => {
  const result = await importCandidates(
    [],
    owner.email,
    async () => [row],
    async () => owner,
  );
  assert(result.source === "ringmaster_breeder" && result.matches.length === 1);
  assert(
    result.matches[0].email === owner.email &&
      result.matches[0].account_type === "family",
  );
});
Deno.test("editable email cannot import another owners profile", async () => {
  const result = await importCandidates(
    [],
    owner.email,
    async () => [row],
    async () => ({ ...owner, email: "someoneelse@example.invalid" }),
  );
  assert(result.matches.length === 0);
});
Deno.test("unverified banned deleted and inactive profiles are excluded", async () => {
  for (
    const auth of [
      { ...owner, email_confirmed_at: null },
      { ...owner, banned_until: "2999-01-01" },
      { ...owner, deleted_at: "2026-01-01" },
      null,
    ]
  ) {
    const result = await importCandidates(
      [],
      owner.email,
      async () => [row],
      async () => auth,
    );
    assert(result.matches.length === 0);
  }
  const result = await importCandidates(
    [],
    owner.email,
    async () => [{ ...row, profile: { ...row.profile, is_active: false } }],
    async () => owner,
  );
  assert(result.matches.length === 0);
});
Deno.test("multiple profiles stay distinct and verify a shared owner once", async () => {
  let reads = 0;
  const result = await importCandidates(
    [],
    owner.email,
    async () => [row, { ...row, id: "second" }],
    async () => {
      reads++;
      return owner;
    },
  );
  assert(result.matches.length === 2 && reads === 1);
});
Deno.test("missing configuration returns no candidates and lookup failures propagate", async () => {
  const empty = await importCandidates(
    [],
    owner.email,
    async () => [],
    async () => owner,
  );
  assert(empty.matches.length === 0);
  let failed = false;
  try {
    await importCandidates([], owner.email, async () => {
      throw Error("upstream failed");
    }, async () => owner);
  } catch {
    failed = true;
  }
  assert(failed);
});
