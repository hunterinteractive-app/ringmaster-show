import { handleReportEmail } from "./handler.ts";
import {
  reportEmailAttemptIdentity,
  selectUnsentReportArtifacts,
} from "../_shared/report_email_delivery.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}

const artifact = (id: string) => ({
  id,
  show_id: "show",
  report_name: "exhibitor_report",
  file_name: `${id}.pdf`,
  artifact_status: "generated",
  storage_bucket: "reports",
  storage_path: `${id}.pdf`,
  metadata: {},
});
const delivery = (
  id: string,
  status = "delivered",
  email = "reader@example.test",
  generation?: number,
) => ({
  artifact_id: id,
  artifact_generation: generation,
  recipient_email: email,
  delivery_status: status,
  sent_at: "2026-11-12T17:00:00Z",
  provider_message_id: "original-message",
});

async function run(options: {
  history?: ReturnType<typeof delivery>[];
  historyError?: boolean;
  body?: Record<string, unknown>;
  allowed?: boolean;
  sanctionNumber?: string;
  sanctionGeneration?: number;
} = {}) {
  const savedFetch = globalThis.fetch;
  const env = {
    SUPABASE_URL: "https://fixture.invalid",
    SUPABASE_ANON_KEY: "test-anon",
    SUPABASE_SERVICE_ROLE_KEY: "test-service",
    RESEND_API_KEY: "test-provider",
    RESEND_FROM_EMAIL: "test@example.test",
  };
  const previous = Object.fromEntries(
    Object.keys(env).map((key) => [key, Deno.env.get(key)]),
  );
  for (const [key, value] of Object.entries(env)) Deno.env.set(key, value);
  const providerCalls: { body: any; key: string | null }[] = [];
  const inserted: any[] = [];
  let downloads = 0;
  let historyLookups = 0;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    const url = new URL(req.url);
    const json = (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      });
    if (url.hostname === "api.resend.com") {
      providerCalls.push({
        body: await req.json(),
        key: req.headers.get("Idempotency-Key"),
      });
      return json({ id: "new-message" });
    }
    assert(
      url.hostname === "fixture.invalid",
      "unexpected real network request",
    );
    if (url.pathname === "/auth/v1/user") {
      return json({ id: "sender", email: "sender@example.test" });
    }
    if (url.pathname.endsWith("/rpc/user_can_email_reports")) {
      return json(options.allowed !== false);
    }
    if (url.pathname.endsWith("/show_report_artifacts")) {
      if (options.sanctionGeneration !== undefined) {
        assert(
          url.searchParams.get("id") === "in.(a,b)",
          "must not expand the club bundle",
        );
        return json(["a", "b"].map((id) => ({
          ...artifact(id),
          report_name: id === "a"
            ? "sweepstakes_report"
            : "breed_results_detail_report",
          generation: options.sanctionGeneration,
          is_current: true,
          metadata: {
            club_name: "English Spot Club",
            breed_name: "English Spot",
            sanction_update_id: "sanction-open-a",
            sanction_number: "ES-NEW",
            section_id: "open-a",
            sweepstakes_email: "reader@example.test",
            sanctioning_body: "NATIONAL CLUB",
            delivery_type: "club",
          },
        })));
      }
      return json([artifact("a"), artifact("b")]);
    }
    if (url.pathname.endsWith("/show_sanctions")) {
      return json([{
        id: "sanction-open-a",
        section_id: "open-a",
        sanction_number: options.sanctionNumber ?? "ES-NEW",
      }]);
    }
    if (url.pathname.endsWith("/show_email_deliveries")) {
      if (req.method === "POST") {
        inserted.push(...await req.json());
        return json(null, 201);
      }
      historyLookups++;
      assert(url.searchParams.get("show_id") === "eq.show");
      assert(url.searchParams.get("artifact_id") === "in.(a,b)");
      assert(url.searchParams.get("sent_at") === "not.is.null");
      assert(
        !url.searchParams.has("subject"),
        "subject must not identify a report",
      );
      assert(
        !url.searchParams.has("delivery_status"),
        "webhook status must not erase a prior send",
      );
      return options.historyError
        ? json({ message: "unavailable" }, 500)
        : json(options.history ?? []);
    }
    if (url.pathname.endsWith("/shows")) {
      return json({
        id: "show",
        name: "Test Show",
        secretary_email: "secretary@example.test",
      });
    }
    if (url.pathname.includes("/storage/v1/object/")) {
      downloads++;
      return new Response("test attachment");
    }
    throw new Error(`Unexpected fixture route: ${req.method} ${url.pathname}`);
  }) as typeof fetch;
  try {
    const response = await handleReportEmail(
      new Request("https://fixture.invalid/send", {
        method: "POST",
        headers: {
          Authorization: "Bearer test-user",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          show_id: "show",
          artifact_ids: ["a", "b"],
          to: "reader@example.test",
          ...options.body,
        }),
      }),
    );
    return {
      status: response.status,
      body: await response.json(),
      providerCalls,
      inserted,
      downloads,
      historyLookups,
    };
  } finally {
    globalThis.fetch = savedFetch;
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

for (
  const status of [
    "sent",
    "delivered",
    "opened",
    "clicked",
    "delivery_delayed",
    "bounced",
    "complained",
  ]
) {
  Deno.test(`provider-accepted ${status} reports are skipped without downloading or emailing`, async () => {
    const result = await run({
      history: [delivery("a", status), delivery("b", status)],
      body: { subject: "Changed subject", message: "A new secretary note" },
    });
    assert(result.status === 200 && result.body.already_sent === true);
    assert(
      result.providerCalls.length === 0 && result.downloads === 0 &&
        result.inserted.length === 0,
    );
  });
}
Deno.test("new files in a partially sent bundle are sent without repeating old files", async () => {
  const result = await run({ history: [delivery("a")] });
  assert(result.providerCalls.length === 1 && result.downloads === 1);
  assert(result.providerCalls[0].body.attachments.length === 1);
  assert(result.providerCalls[0].body.attachments[0].filename === "b.pdf");
  assert(
    result.inserted.length === 1 && result.inserted[0].artifact_id === "b",
  );
});
Deno.test("sanction correction emails only the requested package and records its generation", async () => {
  const options = {
    sanctionGeneration: 2,
    body: { sanction_generations: { a: 2, b: 2 } },
    history: [delivery("a", "delivered", undefined, 1), delivery("b")],
  };
  const first = await run(options);
  assert(first.status === 200 && first.providerCalls.length === 1);
  assert(first.providerCalls[0].body.attachments.length === 2);
  assert(
    first.inserted.length === 2 &&
      first.inserted.every((row) => row.artifact_generation === 2),
  );

  const retry = await run(options);
  assert(retry.providerCalls[0].key === first.providerCalls[0].key);
  const alreadySent = await run({
    ...options,
    history: ["a", "b"].map((id) => delivery(id, "delivered", undefined, 2)),
  });
  assert(
    alreadySent.body.already_sent && alreadySent.providerCalls.length === 0,
  );
});

Deno.test("sanction correction rejects stale numbers, versions, and destination addresses", async () => {
  const options = {
    sanctionGeneration: 2,
    body: { sanction_generations: { a: 2, b: 2 } },
  };
  for (
    const invalid of [
      { ...options, sanctionNumber: "ES-REPLACED" },
      { ...options, sanctionGeneration: 3 },
      { ...options, body: { ...options.body, to: "other@example.test" } },
    ]
  ) {
    const result = await run(invalid);
    assert(result.status === 409 && result.providerCalls.length === 0);
  }
});
Deno.test("an unrelated report or new recipient is not suppressed", async () => {
  const result = await run({
    history: [
      delivery("a", "delivered", "other@example.test"),
      delivery("other"),
    ],
  });
  assert(result.providerCalls.length === 1 && result.downloads === 2);
});
Deno.test("a failed attempt never accepted by the provider can be retried normally", async () => {
  const result = await run({
    history: [{ ...delivery("a", "failed"), sent_at: null } as any],
  });
  assert(result.providerCalls.length === 1 && result.downloads === 2);
});
Deno.test("history lookup failure stops the send", async () => {
  const result = await run({ historyError: true });
  assert(
    result.status === 500 && result.providerCalls.length === 0 &&
      result.downloads === 0,
  );
});
Deno.test("explicit single resend sends again, still requiring permission", async () => {
  const result = await run({
    history: [delivery("a"), delivery("b")],
    body: { force_resend: true },
  });
  assert(
    result.status === 200 && result.providerCalls.length === 1 &&
      result.historyLookups === 0,
  );
  const denied = await run({ allowed: false, body: { force_resend: true } });
  assert(denied.status === 403 && denied.providerCalls.length === 0);
});
Deno.test("bulk resend requires a nonblank explanation and includes it in the email", async () => {
  for (const message of ["", "  \n "]) {
    const result = await run({
      body: { force_resend: true, resend_scope: "bulk", message },
    });
    assert(result.status === 400 && result.providerCalls.length === 0);
  }
  const result = await run({
    body: {
      force_resend: true,
      resend_scope: "bulk",
      message: "Corrected exhibitor name.",
    },
  });
  assert(
    result.status === 200 &&
      result.providerCalls[0].body.html.includes("Corrected exhibitor name."),
  );
});
Deno.test("recipient order/case and separately delivered recipients do not bypass deduplication", async () => {
  const result = await run({
    history: [
      delivery("a"),
      delivery("b"),
      delivery("a", "delivered", "second@example.test"),
      delivery("b", "delivered", "second@example.test"),
    ],
    body: { to: ["SECOND@example.test", "Reader@example.test"] },
  });
  assert(result.body.already_sent && result.providerCalls.length === 0);
});
Deno.test("mixed old and new recipients require separate sends or explicit resend", async () => {
  const result = await run({
    history: [delivery("a")],
    body: { to: ["reader@example.test", "new@example.test"] },
  });
  assert(result.status === 500 && result.providerCalls.length === 0);
});
Deno.test("history is paginated so an earlier send beyond the first page is found", async () => {
  const offsets: number[] = [];
  const result = await selectUnsentReportArtifacts(
    [artifact("a")],
    ["reader@example.test"],
    false,
    async (from) => {
      offsets.push(from);
      return from === 0
        ? Array.from(
          { length: 500 },
          () => delivery("a", "delivered", "other@example.test"),
        )
        : [delivery("a")];
    },
  );
  assert(result.artifacts.length === 0 && offsets.join() === "0,500");
});
Deno.test("normal provider retries reuse a key; explicit resends use new attempts", () => {
  const key = reportEmailAttemptIdentity(
    "show",
    ["A@example.test", "b@example.test"],
    ["b", "a"],
    false,
  );
  assert(
    key ===
      reportEmailAttemptIdentity("show", ["b@example.test", "a@example.test"], [
        "a",
        "b",
      ], false),
  );
  assert(
    key !==
      reportEmailAttemptIdentity(
        "other",
        ["A@example.test", "b@example.test"],
        ["b", "a"],
        false,
      ),
  );
  assert(
    reportEmailAttemptIdentity("show", ["a"], ["a"], true) !==
      reportEmailAttemptIdentity("show", ["a"], ["a"], true),
  );
});
