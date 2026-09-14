import {
  buildCheckinEmailHtml,
  enrichExhibitorNumbers,
  errorMessage,
  loadAllPages,
  prepareDeliveryAttempt,
  retryWindowOpen,
  waveDeliveryKey,
} from "./helpers.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import {
  buildPdfBytes,
  exhibitorName,
  groupVarietyLabel,
  safe,
} from "./pdf.ts";
import { Buffer } from "node:buffer";

let supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const fromEmail = Deno.env.get("CHECKIN_FROM_EMAIL") ??
  "RingMaster Show <noreply@ringmasterone.com>";

function cleanEmail(value: unknown): string {
  return (value ?? "").toString().trim();
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

function emailList(value: unknown): string[] {
  if (!value) return [];

  const values = Array.isArray(value) ? value : String(value).split(/[;,]/);

  return values
    .map((v) => cleanEmail(v))
    .filter((email) => email.length > 0);
}

function validEmailList(value: unknown): {
  valid: string[];
  invalid: string[];
} {
  const emails = emailList(value);

  const valid: string[] = [];
  const invalid: string[] = [];

  for (const email of emails) {
    if (isValidEmail(email)) {
      valid.push(email);
    } else {
      invalid.push(email);
    }
  }

  return { valid, invalid };
}

function emailForExhibitor(entries: Record<string, unknown>[]): string {
  for (const e of entries) {
    const email = safe(e, "email");
    if (email) return email;

    const exhibitorEmail = safe(e, "exhibitor_email");
    if (exhibitorEmail) return exhibitorEmail;
  }
  return "";
}

function safeFileName(value: string): string {
  return value
    .replace(/[^A-Za-z0-9_\-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");
}

function groupByExhibitor(
  entries: Record<string, unknown>[],
  useWaves = false,
): Map<string, Record<string, unknown>[]> {
  const map = new Map<string, Record<string, unknown>[]>();

  for (const e of entries) {
    const exId = safe(e, "exhibitor_id") || "_unknown";
    if (!map.has(exId)) map.set(exId, []);
    map.get(exId)!.push(e);
  }

  for (const list of map.values()) {
    list.sort((a, b) => {
      const sectionCmp =
        safe(a, "section_kind").localeCompare(safe(b, "section_kind")) ||
        Number(a.section_sort_order ?? 0) - Number(b.section_sort_order ?? 0) ||
        safe(a, "section_letter").localeCompare(safe(b, "section_letter"));
      if (useWaves && sectionCmp !== 0) return sectionCmp;
      const tattooCmp = safe(a, "tattoo").localeCompare(safe(b, "tattoo"));
      if (tattooCmp !== 0) return tattooCmp;

      const breedCmp = safe(a, "breed").localeCompare(safe(b, "breed"));
      if (breedCmp !== 0) return breedCmp;

      return groupVarietyLabel(a).localeCompare(groupVarietyLabel(b));
    });
  }

  return map;
}

async function enrichCoopNumbers(
  showId: string,
  coopNumberingMode: string,
  entries: Record<string, unknown>[],
): Promise<void> {
  if (entries.length === 0) return;

  const entryIds = Array.from(
    new Set(
      entries
        .map((entry) => safe(entry, "entry_id") || safe(entry, "id"))
        .filter(Boolean),
    ),
  );

  const animalIdByEntryId = new Map<string, string>();
  const pageSize = 100;

  for (let i = 0; i < entryIds.length; i += pageSize) {
    const chunk = entryIds.slice(i, i + pageSize);

    const { data, error } = await supabase
      .from("entries")
      .select("id, animal_id")
      .in("id", chunk);

    if (error) throw error;

    for (const row of data ?? []) {
      const entryId = String(row.id ?? "").trim();
      const animalId = String(row.animal_id ?? "").trim();

      if (entryId && animalId) {
        animalIdByEntryId.set(entryId, animalId);
      }
    }
  }

  const sectionIds = Array.from(
    new Set(entries.map((entry) => safe(entry, "section_id")).filter(Boolean)),
  );

  const sectionKindById = new Map<string, string>();

  for (let i = 0; i < sectionIds.length; i += pageSize) {
    const chunk = sectionIds.slice(i, i + pageSize);

    const { data, error } = await supabase
      .from("show_sections")
      .select("id, kind")
      .in("id", chunk);

    if (error) throw error;

    for (const row of data ?? []) {
      const sectionId = String(row.id ?? "").trim();
      const kind = String(row.kind ?? "").trim().toLowerCase();

      if (sectionId && kind) {
        sectionKindById.set(sectionId, kind);
      }
    }
  }

  const animalIds = Array.from(new Set(animalIdByEntryId.values()));
  const coopNumberByAnimalAndScope = new Map<string, string>();

  for (let i = 0; i < animalIds.length; i += pageSize) {
    const chunk = animalIds.slice(i, i + pageSize);

    const { data, error } = await supabase
      .from("show_animal_coop_numbers")
      .select("animal_id, scope, coop_number")
      .eq("show_id", showId)
      .in("animal_id", chunk);

    if (error) throw error;

    for (const row of data ?? []) {
      const animalId = String(row.animal_id ?? "").trim();
      const scope = String(row.scope ?? "").trim().toLowerCase();
      const coopNumber = String(row.coop_number ?? "").trim();

      if (!animalId || !scope || !coopNumber) continue;

      coopNumberByAnimalAndScope.set(`${animalId}|${scope}`, coopNumber);
    }
  }

  const normalizedMode = coopNumberingMode.trim().toLowerCase() === "combined"
    ? "combined"
    : "separate";

  for (const entry of entries) {
    const entryId = safe(entry, "entry_id") || safe(entry, "id");
    const animalId = animalIdByEntryId.get(entryId) ?? "";

    const sectionId = safe(entry, "section_id");
    const sectionKind = safe(entry, "section_kind").toLowerCase() ||
      sectionKindById.get(sectionId) ||
      "";

    const scope = normalizedMode === "combined" ? "all" : sectionKind;

    const coopNumber = animalId && scope
      ? coopNumberByAnimalAndScope.get(`${animalId}|${scope}`) ?? ""
      : "";

    entry["animal_id"] = animalId;
    entry["coop_number"] = coopNumber;
  }
}

async function sendEmail({
  to,
  subject,
  html,
  filename,
  pdfBytes,
  replyTo,
  showId,
  exhibitorId,
  waveId = null,
}: {
  to: string;
  subject: string;
  html: string;
  filename: string;
  pdfBytes: Uint8Array;
  replyTo?: string;
  showId: string;
  exhibitorId: string;
  waveId?: string | null;
}): Promise<Record<string, unknown>> {
  const toCheck = validEmailList(to);

  if (toCheck.invalid.length > 0 || toCheck.valid.length === 0) {
    throw new Error(
      `Invalid recipient email: ${
        toCheck.invalid.length > 0 ? toCheck.invalid.join(", ") : to
      }`,
    );
  }

  const replyToCheck = validEmailList(replyTo);
  const replyToList = replyToCheck.valid.length > 0
    ? replyToCheck.valid
    : undefined;

  const bccList = replyToList;

  const payload: Record<string, unknown> = {
    from: fromEmail,
    to: toCheck.valid,
    subject,
    html,
    attachments: [
      {
        filename,
        content: Buffer.from(pdfBytes).toString("base64"),
      },
    ],
  };

  if (replyToList) {
    payload.reply_to = replyToList;
  }

  if (bccList) {
    payload.bcc = bccList;
  }

  // Store the exact payload so retries reuse identical PDF bytes and headers.
  const { error: insertError } = await supabase.from(
    "auto_checkin_email_deliveries",
  )
    .upsert({
      show_id: showId,
      exhibitor_id: exhibitorId,
      wave_id: waveId,
      status: "pending",
      payload,
    }, { onConflict: "show_id,exhibitor_id,wave_id", ignoreDuplicates: true });
  if (insertError) throw insertError;
  const { data: receipt, error: receiptError } = await supabase.from(
    "auto_checkin_email_deliveries",
  )
    .select("status,payload,provider_message_id,first_attempt_at").eq(
      "show_id",
      showId,
    ).eq("exhibitor_id", exhibitorId).filter(
      "wave_id",
      waveId ? "eq" : "is",
      waveId ?? "null",
    ).single();
  if (receiptError) throw receiptError;
  if (receipt.status === "sent") return { id: receipt.provider_message_id };
  if (!retryWindowOpen(receipt.first_attempt_at)) {
    throw new Error(
      "Delivery needs review: provider retry protection has expired; not resending automatically.",
    );
  }
  const attempt = prepareDeliveryAttempt(receipt.payload, payload);
  if (attempt.needsSave) {
    const { error } = await supabase.from("auto_checkin_email_deliveries")
      .update({ payload: attempt.durable })
      .eq("show_id", showId).eq("exhibitor_id", exhibitorId)
      .filter("wave_id", waveId ? "eq" : "is", waveId ?? "null")
      .eq("status", "pending").eq("first_attempt_at", receipt.first_attempt_at)
      .select("first_attempt_at").single();
    if (error) throw error;
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Idempotency-Key": waveDeliveryKey(
        showId,
        exhibitorId,
        waveId,
        attempt.resendId,
      ),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(attempt.providerPayload),
    signal: AbortSignal.timeout(20000),
  });

  const responseText = await response.text();
  let data: Record<string, unknown> = {};

  try {
    data = responseText ? JSON.parse(responseText) : {};
  } catch (_) {
    data = { raw: responseText };
  }

  if (!response.ok) {
    console.error("Resend auto check-in sheet failed", {
      status: response.status,
      body: data,
      to: payload.to,
      reply_to: payload.reply_to,
      bcc: payload.bcc,
    });

    throw new Error(
      `Resend failed ${response.status}: ${
        String(data?.message ?? data?.error ?? responseText)
      }`,
    );
  }

  console.log("Resend auto check-in sheet sent", {
    status: response.status,
    id: data?.id,
    to: payload.to,
    reply_to: payload.reply_to,
    bcc: payload.bcc,
  });

  if (!data.id) throw new Error("Email provider returned no message ID.");
  const { error: saveError } = await supabase.from(
    "auto_checkin_email_deliveries",
  )
    .update({
      status: "sent",
      provider_message_id: String(data.id),
      sent_at: new Date().toISOString(),
      error: null,
      payload: null,
    })
    .eq("show_id", showId).eq("exhibitor_id", exhibitorId).filter(
      "wave_id",
      waveId ? "eq" : "is",
      waveId ?? "null",
    );
  if (saveError) throw saveError;
  return data;
}

async function replyToForShow(show: Record<string, unknown>): Promise<string> {
  const secretaryEmail = safe(show, "secretary_email");

  if (isValidEmail(secretaryEmail)) {
    return secretaryEmail;
  }

  const ownerUserId = safe(show, "owner_user_id");

  if (ownerUserId) {
    const { data, error } = await supabase.auth.admin.getUserById(ownerUserId);

    if (!error) {
      const ownerEmail = cleanEmail(data?.user?.email);
      if (isValidEmail(ownerEmail)) return ownerEmail;
    }

    console.warn(
      `Could not load owner email for show ${safe(show, "id")}: ${
        error?.message ?? "Unknown error"
      }`,
    );
  }

  return "";
}

async function loadEntries(showId: string, waveId: string | null = null) {
  const rows = await loadAllPages<Record<string, unknown>>(async (from, to) => {
    const { data, error } = await supabase.rpc(
      waveId ? "report_wave_checkin_entries" : "report_checkin_entries",
      {
        ...(waveId ? { p_wave_id: waveId } : {}),
        p_show_id: showId,
        p_section_id: null,
        p_include_scratched: false,
      },
    ).order("entry_id").range(from, to);
    if (error) throw error;
    return data ?? [];
  });
  if (new Set(rows.map((r) => safe(r, "entry_id"))).size !== rows.length) {
    throw new Error(
      "Check-in report returned duplicate entry IDs; refusing incomplete delivery.",
    );
  }
  await enrichExhibitorNumbers(rows, async (ids) => {
    const { data, error } = await supabase.from("exhibitors")
      .select("id,exhibitor_number").in("id", ids);
    if (error) throw error;
    return data ?? [];
  });
  return rows;
}

async function loadCheckinLink(showId: string): Promise<string | null> {
  const { data, error } = await supabase.rpc("get_show_checkin_email_link", {
    p_show_id: showId,
  });
  if (error) throw error;
  return data || null;
}

async function processShow(
  show: Record<string, unknown>,
  wave?: Record<string, unknown>,
) {
  const waveId = wave ? String(wave.id) : null;
  const label = wave ? `Wave ${wave.wave_number}` : "All Shows";
  const saveProgress = (emailedAt: string | null, error: string | null) =>
    waveId
      ? supabase.from("show_waves").update({
        sheets_emailed_at: emailedAt,
        email_error: error,
      }).eq("id", waveId)
      : supabase.from("shows").update({
        checkin_sheets_auto_emailed_at: emailedAt,
        checkin_sheets_auto_email_error: error,
      }).eq("id", String(show.id));
  const showId = safe(show, "id");
  const token = crypto.randomUUID();
  const { data: claimed, error: claimError } = await supabase.rpc(
    "claim_auto_checkin_email_run",
    { p_show_id: showId, p_token: token },
  );
  if (claimError) throw claimError;
  if (!claimed) return;
  try {
    if (waveId) {
      const { data, error } = await supabase.rpc("begin_wave_checkin_email", {
        p_wave_id: waveId,
      });
      if (error) throw error;
      if (!data?.length) return;
      wave = data[0];
    }
    const rows = await loadEntries(showId, waveId);
    await enrichCoopNumbers(showId, safe(show, "coop_numbering_mode"), rows);
    const groups = groupByExhibitor(rows, Boolean(waveId));
    const receipts = await loadAllPages<Record<string, unknown>>(
      async (from, to) => {
        const { data, error } = await supabase.from(
          "auto_checkin_email_deliveries",
        )
          .select("exhibitor_id,status,error").eq("show_id", showId).filter(
            "wave_id",
            waveId ? "eq" : "is",
            waveId ?? "null",
          ).order("exhibitor_id").range(from, to);
        if (error) throw error;
        return data ?? [];
      },
    );
    const done = new Set(
      receipts.filter((r) => r.status === "sent" || r.status === "skipped").map(
        (r) => String(r.exhibitor_id),
      ),
    );
    const failures = receipts.filter((r) => r.status === "skipped").map((r) =>
      String(r.error)
    );
    const replyTo = await replyToForShow(show);
    const checkinUrl = await loadCheckinLink(showId);
    let attempted = 0;
    const started = Date.now();
    for (const [exhibitorId, entries] of groups) {
      if (done.has(exhibitorId)) continue;
      if (attempted >= 10 || Date.now() - started > 40000) break;
      attempted++;
      const name = exhibitorName(entries[0]);
      const email = emailForExhibitor(entries);
      const check = validEmailList(email);
      if (!email || !check.valid.length || check.invalid.length) {
        const error = `${name}: missing or invalid email address`;
        const { error: saveError } = await supabase.from(
          "auto_checkin_email_deliveries",
        ).upsert({
          show_id: showId,
          exhibitor_id: exhibitorId,
          wave_id: waveId,
          status: "skipped",
          error,
          payload: null,
        }, { onConflict: "show_id,exhibitor_id,wave_id" });
        if (saveError) throw saveError;
        done.add(exhibitorId);
        failures.push(error);
        continue;
      }
      try {
        const pdfBytes = await buildPdfBytes({
          show,
          sectionLabel: label,
          entries,
          wave,
        });
        await sendEmail({
          to: email,
          subject: `Check-In Sheet — ${show.name}${wave ? ` — ${label}` : ""}`,
          replyTo,
          pdfBytes,
          showId,
          exhibitorId,
          waveId,
          filename: `check_in_${safeFileName(String(show.name))}_${
            safeFileName(name)
          }${wave ? `_${safeFileName(label)}` : ""}.pdf`,
          html: buildCheckinEmailHtml({
            name,
            showName: safe(show, "name"),
            waveLabel: wave ? label : undefined,
            checkinUrl,
          }),
        });
        done.add(exhibitorId);
        await new Promise((resolve) => setTimeout(resolve, 600));
      } catch (error) {
        const message = errorMessage(error);
        failures.push(`${name}: ${message}`);
        const { error: saveError } = await supabase.from(
          "auto_checkin_email_deliveries",
        ).update({ error: message })
          .eq("show_id", showId).eq("exhibitor_id", exhibitorId).filter(
            "wave_id",
            waveId ? "eq" : "is",
            waveId ?? "null",
          );
        if (saveError) throw saveError;
      }
    }
    const remaining = [...groups.keys()].filter((id) => !done.has(id)).length;
    const { error } = await saveProgress(
      remaining === 0 ? new Date().toISOString() : null,
      failures.length
        ? failures.join("; ")
        : remaining
        ? `Sending check-in sheets: ${
          groups.size - remaining
        } of ${groups.size} exhibitors processed; ${remaining} remaining.`
        : null,
    );
    if (error) throw error;
  } catch (error) {
    const message = errorMessage(error);
    console.error("Automatic check-in email preparation failed", {
      showId,
      error: message,
    });
    const { error: saveError } = await saveProgress(null, message);
    if (saveError) console.error(errorMessage(saveError));
  } finally {
    const { error } = await supabase.from("auto_checkin_email_runs").update({
      lease_until: new Date().toISOString(),
    })
      .eq("show_id", showId).eq("lease_token", token);
    if (error) console.error(errorMessage(error));
  }
}

async function run() {
  if (!resendApiKey) throw new Error("Missing RESEND_API_KEY.");
  const started = Date.now();
  const { data: waves, error: waveError } = await supabase.rpc(
    "due_checkin_email_waves",
  );
  if (waveError) throw waveError;
  for (const wave of waves ?? []) {
    if (Date.now() - started > 45000) break;
    const { data: show, error } = await supabase.from("shows").select(
      "id,owner_user_id,name,timezone,secretary_name,secretary_phone,secretary_email,coop_numbering_mode",
    ).eq("id", wave.show_id).single();
    if (error) throw error;
    await processShow(show, wave);
  }
  const enabled = await loadAllPages<Record<string, unknown>>(
    async (from, to) => {
      const { data, error } = await supabase.from("show_wave_settings").select(
        "show_id",
      ).eq("enabled", true).order("show_id").range(from, to);
      if (error) throw error;
      return data ?? [];
    },
  );
  let query = supabase.from("shows")
    .select(
      "id,owner_user_id,name,entry_close_at,secretary_name,secretary_phone,secretary_email,coop_numbering_mode",
    )
    .eq("auto_email_checkin_sheets", true).is(
      "checkin_sheets_auto_emailed_at",
      null,
    )
    .lte("entry_close_at", new Date().toISOString())
    .or("email_sending_disabled.is.null,email_sending_disabled.eq.false")
    .or(
      `end_date.gte.${
        new Date().toISOString().slice(0, 10)
      },and(end_date.is.null,start_date.gte.${
        new Date().toISOString().slice(0, 10)
      })`,
    );
  if (enabled.length) {
    query = query.not(
      "id",
      "in",
      `(${enabled.map((r) => r.show_id).join(",")})`,
    );
  }
  const { data: shows, error } = await query.order("entry_close_at").limit(10);
  if (error) throw error;
  for (const show of shows ?? []) {
    if (Date.now() - started > 45000) break;
    await processShow(show);
  }
}

declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void };
serve(async (req) => {
  const authorization = req.headers.get("authorization") ?? "";
  const key = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : "";
  if (!key) return new Response("Unauthorized", { status: 401 });
  // Validate at PostgREST against a service-only table. This accepts valid
  // rotated service keys without trusting an unverified JWT role claim.
  const caller = createClient(Deno.env.get("SUPABASE_URL") ?? "", key);
  const { error: authError } = await caller.from("auto_checkin_email_runs")
    .select("show_id").limit(0);
  if (authError) return new Response("Unauthorized", { status: 401 });
  supabase = caller;
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  const body = await req.json().catch(() => ({}));
  if (body.dry_run === true) {
    try {
      if (!body.show_id) throw new Error("show_id is required for dry_run");
      const rows = await loadEntries(body.show_id, body.wave_id ?? null);
      const { data: show, error } = await supabase.from("shows").select(
        "id,name,coop_numbering_mode",
      ).eq("id", body.show_id).single();
      if (error) throw error;
      await enrichCoopNumbers(
        body.show_id,
        safe(show, "coop_numbering_mode"),
        rows,
      );
      const groups = groupByExhibitor(rows);
      const checkinUrl = await loadCheckinLink(body.show_id);
      const first = [...groups.values()][0];
      const pdf = first
        ? await buildPdfBytes({
          show,
          sectionLabel: "All Shows",
          entries: first,
        })
        : new Uint8Array();
      return Response.json({
        ok: true,
        dry_run: true,
        entries: rows.length,
        entries_with_exhibitor_number: rows.filter((r) =>
          safe(r, "exhibitor_number")
        ).length,
        exhibitors: groups.size,
        sample_pdf_bytes: pdf.length,
        includes_checkin_link: Boolean(checkinUrl),
      });
    } catch (error) {
      return Response.json({ ok: false, error: errorMessage(error) }, {
        status: 500,
      });
    }
  }
  EdgeRuntime.waitUntil(
    run().catch((error) => console.error(errorMessage(error))),
  );
  return Response.json({ ok: true, accepted: true }, { status: 202 });
});
