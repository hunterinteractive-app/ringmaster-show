import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { findLicenseUserByEmail } from "./license_user_lookup.ts";

const fullPage = Array.from({ length: 1000 }, (_, i) => ({
  id: `other-${i}`,
  email: `other-${i}@example.invalid`,
}));
const secretary = { id: "secretary", email: "secretary@example.invalid" };

function directory(pages: ({ id: string; email?: string }[] | Error)[]) {
  const calls: { page: number; perPage: number }[] = [];
  return {
    calls,
    async listUsers(params: { page: number; perPage: number }) {
      calls.push(params);
      const result = pages[params.page - 1] ?? [];
      return result instanceof Error
        ? { data: { users: [] }, error: result }
        : { data: { users: result }, error: null };
    },
  };
}

Deno.test("secretary beyond the first page is credited to their account", async () => {
  const users = directory([fullPage, [secretary]]);
  assertEquals(await findLicenseUserByEmail(users, secretary.email), secretary);
  assertEquals(users.calls, [
    { page: 1, perPage: 1000 },
    { page: 2, perPage: 1000 },
  ]);
});

Deno.test("lookup keeps searching beyond two full pages", async () => {
  const users = directory([fullPage, fullPage, [secretary]]);
  assertEquals(await findLicenseUserByEmail(users, secretary.email), secretary);
  assertEquals(users.calls.length, 3);
});

Deno.test("matching email ignores case and surrounding whitespace", async () => {
  const users = directory([[{
    ...secretary,
    email: " SECRETARY@Example.Invalid ",
  }]]);
  assertEquals(
    (await findLicenseUserByEmail(users, " Secretary@EXAMPLE.INVALID "))?.id,
    secretary.id,
  );
  assertEquals(users.calls.length, 1);
});

Deno.test("unregistered secretary stays pending only after all pages are searched", async () => {
  const users = directory([fullPage, [{ id: "no-email" }]]);
  assertEquals(await findLicenseUserByEmail(users, secretary.email), null);
  assertEquals(users.calls.length, 2);
});

Deno.test("an exact full final page is followed by an empty page", async () => {
  const users = directory([fullPage]);
  assertEquals(await findLicenseUserByEmail(users, secretary.email), null);
  assertEquals(users.calls.length, 2);
});

Deno.test("later page failures retry fulfillment instead of treating the user as absent", async () => {
  const users = directory([fullPage, new Error("Auth unavailable")]);
  await assertRejects(
    () => findLicenseUserByEmail(users, secretary.email),
    Error,
    "Auth unavailable",
  );
});
