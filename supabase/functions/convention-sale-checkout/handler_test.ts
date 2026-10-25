import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import type Stripe from "npm:stripe@22.6.0";
import type { SupabaseClient } from "npm:@supabase/supabase-js@2.110.2";
import { createConventionSaleHandler } from "./handler.ts";

const claimId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ownerId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
function harness(
  options: {
    signedIn?: boolean;
    verified?: boolean;
    eligible?: boolean;
    tax?: boolean;
    registrations?: boolean;
    quoteAgeMs?: number;
    localityFailure?: boolean;
    legacyOffer?: boolean;
  } = {},
) {
  const calls: { name: string; params: unknown }[] = [];
  const stripe = {
    paymentLinks: {
      retrieve: () =>
        Promise.resolve({
          active: true,
          livemode: false,
          billing_address_collection: "auto",
          automatic_tax: { enabled: options.tax ?? false },
        }),
      listLineItems: () =>
        Promise.resolve({
          has_more: false,
          data: [{
            quantity: 1,
            amount_subtotal: 5000,
            currency: "usd",
            price: {
              id: "price_canonical",
              active: true,
              unit_amount: 5000,
              recurring: null,
            },
          }],
        }),
    },
    tax: {
      registrations: {
        list: () =>
          Promise.resolve({ data: options.registrations ? [{}] : [] }),
      },
    },
    checkout: {
      sessions: {
        create: (params: unknown, request: unknown) => {
          const expires = (params as Stripe.Checkout.SessionCreateParams)
            .expires_at!;
          if (expires < Date.now() / 1000 + 1800) {
            throw new Error("Stripe requires at least 30 minutes to expire");
          }
          calls.push({ name: "stripe", params: { params, request } });
          return Promise.resolve({
            url: "https://checkout.stripe.com/c/pay/test",
          });
        },
      },
    },
  } as unknown as Stripe;
  const verifiedAt = new Date(Date.now() - (options.quoteAgeMs ?? 0))
    .toISOString();
  const db = {
    auth: {
      getUser: (token: string) => {
        calls.push({ name: "auth", params: token });
        return Promise.resolve({
          error: null,
          data: {
            user: options.signedIn === false ? null : {
              id: ownerId,
              email: "buyer@example.invalid",
              email_confirmed_at: options.verified === false
                ? null
                : verifiedAt,
              is_anonymous: false,
            },
          },
        });
      },
    },
    rpc: (name: string, params: unknown) => {
      calls.push({ name, params });
      if (name === "convention_sale_location_check") {
        return Promise.resolve({
          error: null,
          data: { eligible: options.eligible !== false, lookup_needed: true },
        });
      }
      if (name === "convention_sale_location_result") {
        return Promise.resolve({ error: null, data: null });
      }
      return Promise.resolve(
        options.eligible === false
          ? {
            data: null,
            error: {
              message:
                "Your location could not be confirmed inside the sale area.",
            },
          }
          : {
            error: null,
            data: {
              id: claimId,
              secretary_recipient: options.legacyOffer !== true,
              bonus_tokens: 1,
              bonus_months: 2,
              verified_at: verifiedAt,
            },
          },
      );
    },
  } as unknown as SupabaseClient;
  const handler = createConventionSaleHandler({
    stripe,
    db,
    site: "https://sale.example.invalid",
    locality: () => {
      calls.push({ name: "locality", params: null });
      if (options.localityFailure) {
        return Promise.reject(new Error("lookup unavailable"));
      }
      return Promise.resolve({ city: "Reno", state: "NV", status: "resolved" });
    },
  });
  const request = (patch: Record<string, unknown> = {}) =>
    new Request("https://functions.example.invalid", {
      method: "POST",
      headers: {
        Authorization: "Bearer verified-user-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        action: "checkout",
        plan: "single_show",
        request_id: claimId,
        latitude: 39.4861,
        longitude: -119.7911,
        accuracy: 20,
        measured_at: new Date().toISOString(),
        ...patch,
      }),
    });
  return { handler, request, calls };
}
Deno.test("catalog loads without signing in or requesting location", async () => {
  const h = harness();
  const response = await h.handler(h.request({ action: "catalog" }));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).products.length, 3);
  assertEquals(h.calls.length, 0);
});
Deno.test("city/state is captured from the server lookup after the updated notice", async () => {
  const h = harness();
  const response = await h.handler(h.request({
    location_notice_version: "2026-10-25-locality",
    city: "Forged",
    state: "XX",
  }));
  assertEquals(response.status, 200);
  assertEquals(
    h.calls.find((c) => c.name === "convention_sale_location_result")?.params,
    {
      p_id: claimId,
      p_user_id: ownerId,
      p_city: "Reno",
      p_state: "NV",
      p_status: "resolved",
    },
  );
});
Deno.test("old tabs do not save city/state before displaying the new notice", async () => {
  const h = harness();
  assertEquals((await h.handler(h.request())).status, 200);
  assertEquals(
    h.calls.some((c) =>
      c.name === "locality" || c.name.startsWith("convention_sale_location")
    ),
    false,
  );
});
Deno.test("outside-area checks save locality but cannot create a payment", async () => {
  const h = harness({ eligible: false });
  assertEquals(
    (await h.handler(
      h.request({ location_notice_version: "2026-10-25-locality" }),
    )).status,
    400,
  );
  assertEquals(
    h.calls.some((c) => c.name === "convention_sale_location_result"),
    true,
  );
  assertEquals(
    h.calls.some((c) =>
      c.name === "convention_sale_claim_secretary" || c.name === "stripe"
    ),
    false,
  );
});
Deno.test("a locality provider failure does not block eligible checkout", async () => {
  const h = harness({ localityFailure: true });
  assertEquals(
    (await h.handler(
      h.request({ location_notice_version: "2026-10-25-locality" }),
    )).status,
    200,
  );
  const saved = h.calls.find((c) =>
    c.name === "convention_sale_location_result"
  )?.params as Record<string, unknown>;
  assertEquals(saved.p_status, "unavailable");
  assertEquals(saved.p_city, null);
  assertEquals(saved.p_state, null);
});
Deno.test("unauthenticated and unverified buyers cannot start checkout", async () => {
  for (const options of [{ signedIn: false }, { verified: false }]) {
    const h = harness(options);
    const response = await h.handler(h.request());
    assertEquals(response.status, options.signedIn === false ? 401 : 403);
    assertEquals(h.calls.map((c) => c.name), ["auth"]);
  }
});
Deno.test("server eligibility rejection prevents Stripe checkout creation", async () => {
  const h = harness({ eligible: false });
  const response = await h.handler(h.request());
  assertEquals(response.status, 400);
  assertStringIncludes((await response.json()).error, "inside the sale area");
  assertEquals(h.calls.some((c) => c.name === "stripe"), false);
});
Deno.test("account, price and bonus come from authenticated server records", async () => {
  const h = harness();
  const response = await h.handler(
    h.request({
      user_id: "attacker",
      bonus_tokens: 999,
      price_id: "price_cheaper",
    }),
  );
  assertEquals(response.status, 200);
  const rpc = h.calls.find((c) => c.name === "convention_sale_claim_secretary")!
    .params as Record<string, unknown>;
  assertEquals(rpc.p_user_id, ownerId);
  assertEquals(rpc.p_price_id, "price_canonical");
  assertEquals(rpc.p_amount_cents, 5000);
  assertEquals(rpc.bonus_tokens, undefined);
  const stripe = h.calls.find((c) => c.name === "stripe")!.params as {
    params: Stripe.Checkout.SessionCreateParams;
    request: { idempotencyKey: string };
  };
  assertEquals(stripe.params.metadata?.convention_claim_id, claimId);
  assertEquals(stripe.params.metadata?.convention_recipient, "secretary");
  assertEquals(
    stripe.params.custom_fields?.map(
      (f) => [f.key, f.label.custom, f.optional],
    ),
    [
      ["showsecretaryname", "Show Secretary Name", false],
      ["showsecretaryemail", "Show Secretary Email", false],
    ],
  );
  assertStringIncludes(
    (stripe.params.custom_text!.submit as { message: string }).message,
    "Show Secretary Email",
  );
  assertEquals(stripe.params.client_reference_id, claimId);
  assertEquals(stripe.params.line_items, [{
    price: "price_canonical",
    quantity: 1,
  }]);
  assertEquals(stripe.request.idempotencyKey, `convention-${claimId}`);
  assertEquals("payment_method_types" in stripe.params, false);
  assertEquals("latitude" in stripe.params, false);
  assertEquals(
    stripe.params.success_url,
    `https://sale.example.invalid/#/convention-sale?purchase=${claimId}`,
  );
});
Deno.test("retry of an already-issued legacy offer retains its original buyer and payload", async () => {
  const h = harness({ legacyOffer: true });
  assertEquals((await h.handler(h.request())).status, 200);
  const { params } = h.calls.find((c) => c.name === "stripe")!.params as {
    params: Stripe.Checkout.SessionCreateParams;
  };
  assertEquals(params.custom_fields, undefined);
  assertEquals(params.metadata?.convention_recipient, undefined);
  assertStringIncludes(
    (params.custom_text!.submit as { message: string }).message,
    "signed-in RingMaster account",
  );
});
Deno.test("retry uses identical Stripe payload and idempotency key", async () => {
  const h = harness();
  await h.handler(h.request());
  await h.handler(h.request());
  const requests = h.calls.filter((c) => c.name === "stripe");
  assertEquals(requests.length, 2);
  assertEquals(requests[0].params, requests[1].params);
});

Deno.test("a late checkout retry still meets Stripe's minimum expiration window", async () => {
  const h = harness({ quoteAgeMs: 14 * 60 * 1000 });
  const response = await h.handler(h.request());
  assertEquals(response.status, 200);
  const request = h.calls.find((c) => c.name === "stripe")!.params as {
    params: Stripe.Checkout.SessionCreateParams;
  };
  assertEquals(request.params.expires_at! - Date.now() / 1000 >= 1800, true);
});
Deno.test("automatic tax cannot be enabled without an active registration", async () => {
  const h = harness({ tax: true });
  const response = await h.handler(h.request());
  assertEquals(response.status, 503);
  assertEquals(h.calls.some((c) => c.name === "stripe"), false);
});
Deno.test("canonical automatic tax is preserved when registration is active", async () => {
  const h = harness({ tax: true, registrations: true });
  const response = await h.handler(h.request());
  assertEquals(response.status, 200);
  const request = h.calls.find((c) => c.name === "stripe")!.params as {
    params: Stripe.Checkout.SessionCreateParams;
  };
  assertEquals(request.params.automatic_tax?.enabled, true);
});
