import {
  buildCheckinEmailHtml,
  enrichExhibitorNumbers,
  errorMessage,
  loadAllPages,
  prepareDeliveryAttempt,
  retryWindowOpen,
} from "./helpers.ts";
function assert(value: unknown) {
  if (!value) throw new Error("Assertion failed");
}

Deno.test("explicit resends get fresh content and a separate retry-safe delivery key", () => {
  const resendId = "68f6f0c1-0d4e-41e6-b92e-01a7c33acf49";
  const fresh = {
    html: "Updated check-in link",
    attachments: [{ content: "new-pdf" }],
  };
  const attempt = prepareDeliveryAttempt({ _resend_id: resendId }, fresh);
  assert(attempt.needsSave && attempt.providerPayload.html === fresh.html);
  assert(!("_resend_id" in attempt.providerPayload));
  assert(
    waveDeliveryKey("s", "e", "w", resendId) !== waveDeliveryKey("s", "e", "w"),
  );
  const retry = prepareDeliveryAttempt(attempt.durable, {
    ...fresh,
    html: "Later edit",
  });
  assert(!retry.needsSave && retry.providerPayload.html === fresh.html);
  assert(
    waveDeliveryKey("s", "e", "w", retry.resendId) ===
      waveDeliveryKey("s", "e", "w", resendId),
  );
  const original = prepareDeliveryAttempt(fresh, {
    ...fresh,
    html: "Later edit",
  });
  assert(
    !original.needsSave && original.resendId === null &&
      original.providerPayload.html === fresh.html,
  );
});

Deno.test("check-in email links appear only when a portal URL is provided", () => {
  const url = `https://checkin.ringmasterone.com/#/checkin?token=${
    "a".repeat(64)
  }`;
  for (const waveLabel of [undefined, "Wave 2"]) {
    const html = buildCheckinEmailHtml({
      name: "Test",
      showName: "Show",
      waveLabel,
      checkinUrl: url,
    });
    assert(html.includes(`href="${url}"`));
    assert(html.includes("Open the check-in page"));
    assert(html.includes("exhibitor number and last name"));
    assert(html.includes("scheduled check-in window"));
    assert(html.includes("Entries tab") === Boolean(waveLabel));
    const without = buildCheckinEmailHtml({
      name: "Test",
      showName: "Show",
      waveLabel,
    });
    assert(
      !without.includes("href=") && !without.includes("Open the check-in page"),
    );
  }
});
Deno.test("check-in email escapes exhibitor and show text", () => {
  const html = buildCheckinEmailHtml({
    name: '<a href="bad">Name</a>',
    showName: "Show & Friends",
  });
  assert(!html.includes('<a href="bad">'));
  assert(html.includes("Show &amp; Friends"));
});
Deno.test("exhibitor numbers use each entered exhibitor and batch large shows", async () => {
  const entries: Record<string, unknown>[] = Array.from(
    { length: 207 },
    (_, i) => ({
      exhibitor_id: `e${i % 205}`,
      household_id: "shared-household",
    }),
  );
  const calls: string[][] = [];
  await enrichExhibitorNumbers(entries, (ids) => {
    calls.push(ids);
    return Promise.resolve(ids.map((id) => ({
      id,
      exhibitor_number: 1000 + Number(id.slice(1)),
    })));
  });
  assert(calls.length === 3 && calls[2].length === 5);
  assert(entries[0].exhibitor_number === "1000");
  assert(entries[1].exhibitor_number === "1001");
  assert(entries[205].exhibitor_number === "1000");
});
Deno.test("failed exhibitor lookup stops preparation without guessing numbers", async () => {
  const entries = [{ exhibitor_id: "e1" }];
  let threw = false;
  try {
    await enrichExhibitorNumbers(
      entries,
      () => Promise.reject(new Error("database unavailable")),
    );
  } catch {
    threw = true;
  }
  assert(threw && !("exhibitor_number" in entries[0]));
});
Deno.test("loads 2006 entries despite a smaller server cap", async () => {
  const entries = Array.from({ length: 2006 }, (_, id) => ({ id }));
  const result = await loadAllPages((from, to) =>
    Promise.resolve(entries.slice(from, Math.min(to + 1, from + 137)))
  );
  assert(
    result.length === 2006 && new Set(result.map((r) => r.id)).size === 2006,
  );
  assert(result[2005].id === 2005);
});
Deno.test("empty report stops immediately", async () => {
  let calls = 0;
  assert(
    (await loadAllPages(() => {
      calls++;
      return Promise.resolve([]);
    })).length === 0,
  );
  assert(calls === 1);
});
Deno.test("page errors prevent partial results", async () => {
  let calls = 0;
  let threw = false;
  try {
    await loadAllPages(() => {
      if (calls++) throw new Error("database unavailable");
      return Promise.resolve([1]);
    });
  } catch {
    threw = true;
  }
  assert(threw);
});
Deno.test("structured database errors remain readable", () => {
  assert(
    errorMessage({
      code: "57014",
      message: "statement timeout",
      details: "report read",
    }) === "57014: statement timeout: report read",
  );
  assert(errorMessage(new Error("provider failure")) === "provider failure");
});
Deno.test("uncertain sends stop before provider idempotency expires", () => {
  const start = "2026-09-11T00:00:00Z";
  assert(retryWindowOpen(start, Date.parse(start) + 3600000));
  assert(!retryWindowOpen(start, Date.parse(start) + 24 * 3600000));
});

import { waveDeliveryKey, waveSheetNote } from "./helpers.ts";
Deno.test("each exhibitor wave has an independent stable delivery key", () => {
  assert(
    waveDeliveryKey("show", "exhibitor", "wave1") !==
      waveDeliveryKey("show", "exhibitor", "wave2"),
  );
  assert(
    waveDeliveryKey("show", "exhibitor", "wave1") ===
      "auto-checkin/show/exhibitor/wave1",
  );
  assert(
    waveDeliveryKey("show", "exhibitor", null) ===
      "auto-checkin/show/exhibitor",
  );
  assert(waveSheetNote.includes("Entries tab"));
});
