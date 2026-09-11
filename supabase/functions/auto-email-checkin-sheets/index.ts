import { errorMessage, loadAllPages, retryWindowOpen } from "./helpers.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import PDFDocument from "npm:pdfkit@0.15.0";
import { Buffer } from "node:buffer";

let supabase = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
const fromEmail =
  Deno.env.get("CHECKIN_FROM_EMAIL") ??
  "RingMaster Show <noreply@ringmasterone.com>";

function safe(row: Record<string, unknown>, key: string): string {
  return (row[key] ?? "").toString().trim();
}

function cleanEmail(value: unknown): string {
  return (value ?? "").toString().trim();
}

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

function emailList(value: unknown): string[] {
  if (!value) return [];

  const values = Array.isArray(value)
    ? value
    : String(value).split(/[;,]/);

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

function money(value: unknown): string {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return "$—";
  return `$${n.toFixed(2)}`;
}

function exhibitorName(entry: Record<string, unknown>): string {
  return safe(entry, "exhibitor_label") || "(Unknown Exhibitor)";
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

function groupVarietyLabel(row: Record<string, unknown>): string {
  const groupName = safe(row, "group_name");
  const variety = safe(row, "variety");

  if (groupName && variety) return `${groupName} / ${variety}`;
  if (groupName) return groupName;
  return variety;
}

function displayAgeClassOnly(raw: string): string {
  const lower = raw.toLowerCase();
  if (lower.includes("senior")) return "Senior";
  if (lower.includes("intermediate")) return "Intermediate";
  if (lower.includes("junior")) return "Junior";
  return raw;
}

function groupByExhibitor(
  entries: Record<string, unknown>[],
): Map<string, Record<string, unknown>[]> {
  const map = new Map<string, Record<string, unknown>[]>();

  for (const e of entries) {
    const exId = safe(e, "exhibitor_id") || "_unknown";
    if (!map.has(exId)) map.set(exId, []);
    map.get(exId)!.push(e);
  }

  for (const list of map.values()) {
    list.sort((a, b) => {
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

  const normalizedMode =
    coopNumberingMode.trim().toLowerCase() === "combined"
      ? "combined"
      : "separate";

  for (const entry of entries) {
    const entryId = safe(entry, "entry_id") || safe(entry, "id");
    const animalId = animalIdByEntryId.get(entryId) ?? "";

    const sectionId = safe(entry, "section_id");
    const sectionKind =
      safe(entry, "section_kind").toLowerCase() ||
      sectionKindById.get(sectionId) ||
      "";

    const scope = normalizedMode === "combined" ? "all" : sectionKind;

    const coopNumber =
      animalId && scope
        ? coopNumberByAnimalAndScope.get(`${animalId}|${scope}`) ?? ""
        : "";

    entry["animal_id"] = animalId;
    entry["coop_number"] = coopNumber;
  }
}

function drawText(doc: { text(text: string, options: object): unknown }, text: string, options = {}) {
  doc.text(text || "", options);
}

function buildPdfBytes({
  show,
  sectionLabel,
  entries,
}: {
  show: Record<string, unknown>;
  sectionLabel: string;
  entries: Record<string, unknown>[];
}): Promise<Uint8Array> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "LETTER",
      margin: 28,
      bufferPages: true,
    });

    const chunks: Uint8Array[] = [];

    doc.on("data", (chunk: Uint8Array) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    const first = entries[0] ?? {};
    const name = exhibitorName(first);
    const allShows = money(first["balance_due_all_shows"]);
    const thisShow = money(first["balance_due_this_show"]);

    doc.fontSize(14).font("Helvetica-Bold").text(
      safe(show, "name") || "RingMaster Show",
      { align: "center" },
    );

    doc.moveDown(0.2);
    doc.fontSize(11).font("Helvetica").text(sectionLabel, { align: "center" });
    doc.moveDown(0.2);
    doc.fontSize(12).font("Helvetica-Bold").text("Exhibitor Check-In Sheet", {
      align: "center",
    });

    doc.moveDown();

    doc.fontSize(11).font("Helvetica-Bold").text("Balance Due", {
      align: "right",
      underline: true,
    });
    doc.fontSize(10).text(`All Shows: ${allShows}`, { align: "right" });
    doc.text(`This Show: ${thisShow}`, { align: "right" });

    doc.moveDown();

    doc.rect(doc.x, doc.y, 540, 24).fillAndStroke("#e5e5e5", "#000000");

    doc.fillColor("#000000");
    doc.fontSize(11).font("Helvetica-Bold");
    doc.text(name, 38, doc.y - 19);
    doc.text(`Number Entered  ${entries.length}`, 380, doc.y - 13);

    doc.moveDown(1.2);

    const addressLines = [
      safe(first, "address_line1"),
      safe(first, "address_line2"),
      `${safe(first, "city")}${
        safe(first, "city") && safe(first, "state") ? ", " : ""
      }${safe(first, "state")} ${safe(first, "zip")}`.trim(),
      safe(first, "phone") ? `Phone: ${safe(first, "phone")}` : "",
      safe(first, "email") ? `Email: ${safe(first, "email")}` : "",
    ].filter(Boolean);

    doc.fontSize(9).font("Helvetica");
    for (const line of addressLines) drawText(doc, line);

    doc.moveDown();

    doc.font("Helvetica-Bold").text("Show Secretary:");
    doc.font("Helvetica");
    drawText(doc, safe(show, "secretary_name") || "(Not set)");
    drawText(doc, safe(show, "secretary_phone"));
    drawText(doc, safe(show, "secretary_email"));

    doc.moveDown();

    doc.fontSize(9);
    doc.text(
      "» If there are any problems with your entry as shown below please reach out to the show secretary.",
    );
    doc.text(
      "» No corrections or changes can be made at the judging table or after the show starts.",
    );
    doc.text("» A ? in any column indicates the correct information is not known.");

    doc.moveDown();

    const startX = 28;
    let y = doc.y;
    const cols = [
      { label: "Ear #", width: 60 },
      { label: "Coop #", width: 55 },
      { label: "Breed", width: 110 },
      { label: "Group / Variety", width: 150 },
      { label: "Class", width: 70 },
      { label: "Sex", width: 45 },
      { label: "Fur", width: 35 },
    ];

    function row(values: string[], header = false) {
      let x = startX;
      const rowHeight = header ? 22 : 26;

      if (y + rowHeight > 740) {
        doc.addPage();
        y = 28;
      }

      for (let i = 0; i < cols.length; i++) {
        doc
          .rect(x, y, cols[i].width, rowHeight)
          .fillAndStroke(header ? "#e5e5e5" : "#ffffff", "#000000");

        doc.fillColor("#000000");
        doc.fontSize(8).font(header ? "Helvetica-Bold" : "Helvetica");
        doc.text(values[i] ?? "", x + 3, y + 6, {
          width: cols[i].width - 6,
          height: rowHeight - 6,
        });

        x += cols[i].width;
      }

      y += rowHeight;
    }

    row(cols.map((c) => c.label), true);

    for (const e of entries) {
      const furMark =
        safe(e, "is_fur").toLowerCase() === "true" ||
        safe(e, "class_name").toLowerCase().includes("fur")
          ? "X"
          : "";

      row([
        safe(e, "animal_name") || safe(e, "tattoo"),
        safe(e, "coop_number"),
        safe(e, "breed"),
        groupVarietyLabel(e),
        displayAgeClassOnly(safe(e, "class_name")),
        safe(e, "sex"),
        furMark,
      ]);
    }

    doc.moveDown();
    doc.fontSize(9).text("RingMaster Show", 28, 760);
    doc.end();
  });
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
}: {
  to: string;
  subject: string;
  html: string;
  filename: string;
  pdfBytes: Uint8Array;
  replyTo?: string;
  showId: string;
  exhibitorId: string;
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
  const {error: insertError} = await supabase.from("auto_checkin_email_deliveries")
    .upsert({show_id: showId, exhibitor_id: exhibitorId, status: "pending", payload},
      {onConflict: "show_id,exhibitor_id", ignoreDuplicates: true});
  if (insertError) throw insertError;
  const {data: receipt, error: receiptError} = await supabase.from("auto_checkin_email_deliveries")
    .select("status,payload,provider_message_id,first_attempt_at").eq("show_id",showId).eq("exhibitor_id",exhibitorId).single();
  if (receiptError) throw receiptError;
  if (receipt.status === "sent") return {id: receipt.provider_message_id};
  if (!retryWindowOpen(receipt.first_attempt_at)) {
    throw new Error("Delivery needs review: provider retry protection has expired; not resending automatically.");
  }
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      "Idempotency-Key": `auto-checkin/${showId}/${exhibitorId}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(receipt.payload),
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
  const {error: saveError} = await supabase.from("auto_checkin_email_deliveries")
    .update({status: "sent", provider_message_id: String(data.id), sent_at: new Date().toISOString(), error: null, payload: null})
    .eq("show_id",showId).eq("exhibitor_id",exhibitorId);
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

async function loadEntries(showId: string) {
  const rows = await loadAllPages<Record<string, unknown>>(async (from, to) => {
    const {data, error} = await supabase.rpc("report_checkin_entries", {
      p_show_id: showId, p_section_id: null, p_include_scratched: false,
    }).order("entry_id").range(from, to);
    if (error) throw error;
    return data ?? [];
  });
  if (new Set(rows.map(r => safe(r,"entry_id"))).size !== rows.length) {
    throw new Error("Check-in report returned duplicate entry IDs; refusing incomplete delivery.");
  }
  return rows;
}

async function processShow(show: Record<string, unknown>) {
  const showId = safe(show,"id");
  const token = crypto.randomUUID();
  const {data: claimed,error: claimError} = await supabase.rpc("claim_auto_checkin_email_run",{p_show_id:showId,p_token:token});
  if (claimError) throw claimError;
  if (!claimed) return;
  try {
    const rows = await loadEntries(showId);
    await enrichCoopNumbers(showId,safe(show,"coop_numbering_mode"),rows);
    const groups = groupByExhibitor(rows);
    const receipts = await loadAllPages<Record<string,unknown>>(async(from,to) => {
      const {data,error} = await supabase.from("auto_checkin_email_deliveries")
        .select("exhibitor_id,status,error").eq("show_id",showId).order("exhibitor_id").range(from,to);
      if(error) throw error;
      return data ?? [];
    });
    const done = new Set(receipts.filter(r=>r.status === "sent" || r.status === "skipped").map(r=>String(r.exhibitor_id)));
    const failures = receipts.filter(r=>r.status === "skipped").map(r=>String(r.error));
    const replyTo = await replyToForShow(show);
    let attempted = 0;
    const started = Date.now();
    for (const [exhibitorId, entries] of groups) {
      if(done.has(exhibitorId)) continue;
      if(attempted >= 10 || Date.now()-started > 40000) break;
      attempted++;
      const name=exhibitorName(entries[0]);
      const email=emailForExhibitor(entries);
      const check=validEmailList(email);
      if(!email || !check.valid.length || check.invalid.length) {
        const error=`${name}: missing or invalid email address`;
        const {error: saveError}=await supabase.from("auto_checkin_email_deliveries").upsert({
          show_id:showId,exhibitor_id:exhibitorId,status:"skipped",error,payload:null,
        });
        if(saveError) throw saveError;
        done.add(exhibitorId); failures.push(error); continue;
      }
      try {
        const pdfBytes=await buildPdfBytes({show,sectionLabel:"All Shows",entries});
        await sendEmail({to:email,subject:`Check-In Sheet — ${show.name}`,replyTo,pdfBytes,
          showId,exhibitorId,filename:`check_in_${safeFileName(String(show.name))}_${safeFileName(name)}.pdf`,
          html:`<p>Hello ${name},</p><p>Your check-in sheet for <strong>${show.name}</strong> is attached.</p><p>Please review your entries and contact the show secretary if anything needs corrected.</p><p>Thank you,<br>RingMaster Show</p>`});
        done.add(exhibitorId);
        await new Promise(resolve=>setTimeout(resolve,600));
      } catch(error) {
        const message=errorMessage(error);
        failures.push(`${name}: ${message}`);
        const {error: saveError}=await supabase.from("auto_checkin_email_deliveries").update({error:message})
          .eq("show_id",showId).eq("exhibitor_id",exhibitorId);
        if(saveError) throw saveError;
      }
    }
    const remaining=[...groups.keys()].filter(id=>!done.has(id)).length;
    const {error}=await supabase.from("shows").update({
      checkin_sheets_auto_emailed_at:remaining === 0 ? new Date().toISOString() : null,
      checkin_sheets_auto_email_error: failures.length ? failures.join("; ") : remaining ? `Sending check-in sheets: ${groups.size-remaining} of ${groups.size} exhibitors processed; ${remaining} remaining.` : null,
    }).eq("id",showId);
    if(error) throw error;
  } catch(error) {
    const message=errorMessage(error);
    console.error("Automatic check-in email preparation failed",{showId,error:message});
    const {error: saveError}=await supabase.from("shows").update({checkin_sheets_auto_email_error:message}).eq("id",showId);
    if(saveError) console.error(errorMessage(saveError));
  } finally {
    const {error}=await supabase.from("auto_checkin_email_runs").update({lease_until:new Date().toISOString()})
      .eq("show_id",showId).eq("lease_token",token);
    if(error) console.error(errorMessage(error));
  }
}

async function run() {
  if(!resendApiKey) throw new Error("Missing RESEND_API_KEY.");
  const {data:shows,error}=await supabase.from("shows")
    .select("id,owner_user_id,name,entry_close_at,secretary_name,secretary_phone,secretary_email,coop_numbering_mode")
    .eq("auto_email_checkin_sheets",true).is("checkin_sheets_auto_emailed_at",null)
    .lte("entry_close_at",new Date().toISOString())
    .or("email_sending_disabled.is.null,email_sending_disabled.eq.false")
    .or(`end_date.gte.${new Date().toISOString().slice(0,10)},and(end_date.is.null,start_date.gte.${new Date().toISOString().slice(0,10)})`)
    .order("entry_close_at").limit(10);
  if(error) throw error;
  for(const show of shows ?? []) await processShow(show);
}

declare const EdgeRuntime: {waitUntil(promise: Promise<unknown>): void};
serve(async (req) => {
  const authorization=req.headers.get("authorization") ?? "";
  const key=authorization.startsWith("Bearer ") ? authorization.slice(7).trim() : "";
  if(!key) return new Response("Unauthorized",{status:401});
  // Validate at PostgREST against a service-only table. This accepts valid
  // rotated service keys without trusting an unverified JWT role claim.
  const caller=createClient(Deno.env.get("SUPABASE_URL") ?? "",key);
  const {error: authError}=await caller.from("auto_checkin_email_runs").select("show_id").limit(0);
  if(authError) return new Response("Unauthorized",{status:401});
  supabase=caller;
  if(req.method !== "POST") return new Response("Method not allowed",{status:405});
  const body=await req.json().catch(()=>({}));
  if(body.dry_run === true) {
    try {
      if(!body.show_id) throw new Error("show_id is required for dry_run");
      const rows=await loadEntries(body.show_id);
      const {data:show,error}=await supabase.from("shows").select("id,name,coop_numbering_mode").eq("id",body.show_id).single();
      if(error) throw error;
      await enrichCoopNumbers(body.show_id,safe(show,"coop_numbering_mode"),rows);
      const groups=groupByExhibitor(rows);
      const first=[...groups.values()][0];
      const pdf=first ? await buildPdfBytes({show,sectionLabel:"All Shows",entries:first}) : new Uint8Array();
      return Response.json({ok:true,dry_run:true,entries:rows.length,exhibitors:groups.size,sample_pdf_bytes:pdf.length});
    } catch(error) {return Response.json({ok:false,error:errorMessage(error)},{status:500});}
  }
  EdgeRuntime.waitUntil(run().catch(error=>console.error(errorMessage(error))));
  return Response.json({ok:true,accepted:true},{status:202});
});
