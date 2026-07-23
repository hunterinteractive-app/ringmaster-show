// @ts-nocheck
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return json({
      error: "Method not allowed"
    }, 405);
  }
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
    const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey || !resendApiKey || !resendFromEmail) {
      return json({
        error: "Missing required environment variables: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY, RESEND_FROM_EMAIL"
      }, 500);
    }
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) {
      return json({
        error: "Missing Authorization header"
      }, 401);
    }
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) {
      console.error("Authentication failed", userError);
      return json({
        error: "Unauthorized"
      }, 401);
    }
    const body = await req.json();
    const showId = body.show_id?.trim();
    const artifactIds = Array.isArray(body.artifact_ids) ? body.artifact_ids.map((value)=>String(value ?? "").trim()).filter((value)=>value.length > 0) : [];
    const rawTo = body.to;
    const subjectOverride = body.subject?.trim();
    const message = body.message?.trim() ?? "";
    const requestedReplyTo = body.reply_to?.trim();
    const forceResend = body.force_resend === true;
    if (!showId) {
      return json({
        error: "show_id is required"
      }, 400);
    }
    if (artifactIds.length === 0) {
      return json({
        error: "artifact_ids is required"
      }, 400);
    }
    if (!rawTo || Array.isArray(rawTo) && rawTo.length === 0) {
      return json({
        error: "to is required"
      }, 400);
    }
    const recipients = emailList(rawTo);
    if (!recipients) {
      return json({
        error: "No valid recipient emails supplied"
      }, 400);
    }
    /*
     * Use the centralized database permission function.
     *
     * Signature:
     * public.user_can_email_reports(uuid, uuid)
     *
     * Expected parameter names:
     * p_show_id
     * p_user_id
     */ const { data: permissionResult, error: permissionError } = await adminClient.rpc("user_can_email_reports", {
      p_show_id: showId,
      p_user_id: user.id
    });
    if (permissionError) {
      console.error("Email permission check failed", {
        show_id: showId,
        user_id: user.id,
        error: permissionError
      });
      return json({
        error: `Email permission check failed: ${permissionError.message}`
      }, 500);
    }
    if (permissionResult !== true) {
      console.warn("Report email permission denied", {
        show_id: showId,
        user_id: user.id,
        permission_result: permissionResult
      });
      return json({
        error: "You do not have permission to email reports for this show."
      }, 403);
    }
    const { data: artifactRows, error: artifactError } = await adminClient.from("show_report_artifacts").select(`
          id,
          show_id,
          report_name,
          file_name,
          artifact_status,
          storage_bucket,
          storage_path,
          generated_at,
          metadata
        `).eq("show_id", showId).in("id", artifactIds);
    if (artifactError) {
      return json({
        error: `Artifact lookup failed: ${artifactError.message}`
      }, 500);
    }
    let artifacts = artifactRows ?? [];
    if (artifacts.length === 0) {
      return json({
        error: "No report artifacts found."
      }, 404);
    }
    const foundIds = new Set(artifacts.map((artifact)=>artifact.id));
    const missingIds = artifactIds.filter((artifactId)=>!foundIds.has(artifactId));
    if (missingIds.length > 0) {
      return json({
        error: `Some artifacts were not found: ${missingIds.join(", ")}`
      }, 404);
    }
    // A breed club must receive one email containing every current report
    // for that breed across all applicable show sections.
    const anchorMeta = artifacts[0]?.metadata ?? {};
    const anchorBreed = String(anchorMeta["breed_name"] ?? "").trim();
    const anchorClub = String(anchorMeta["club_name"] ?? "").trim();
    const anchorEmail = String(anchorMeta["sweepstakes_email"] ?? "").trim().toLowerCase();
    const anchorSanctioningBody = String(anchorMeta["sanctioning_body"] ?? "").trim().toUpperCase();
    if (anchorBreed || anchorClub || anchorEmail) {
      const groupedReportNames = anchorSanctioningBody === "NATIONAL CLUB" ? [
        "sweepstakes_report",
        "breed_results_detail_report"
      ] : [
        ...new Set(artifacts.map((artifact)=>artifact.report_name))
      ];
      const { data: groupedRows, error: groupedError } = await adminClient.from("show_report_artifacts").select(`
          id,
          show_id,
          report_name,
          file_name,
          artifact_status,
          storage_bucket,
          storage_path,
          generated_at,
          metadata,
          generation,
          section_ids
        `).eq("show_id", showId).eq("artifact_status", "generated").eq("is_current", true).in("report_name", groupedReportNames);
      if (groupedError) {
        return json({
          error: `Breed report grouping failed: ${groupedError.message}`
        }, 500);
      }
      const normalized = (value)=>String(value ?? "").trim().toLowerCase();
      const matchingRows = (groupedRows ?? []).filter((row)=>{
        const meta = row.metadata ?? {};
        const rowBreed = normalized(meta["breed_name"]);
        const rowClub = normalized(meta["club_name"]);
        const rowEmail = normalized(meta["sweepstakes_email"]);
        if (anchorBreed && rowBreed !== normalized(anchorBreed)) return false;
        if (anchorClub && rowClub !== normalized(anchorClub)) return false;
        if (anchorEmail && rowEmail !== anchorEmail) return false;
        return true;
      });
      const logicalArtifacts = new Map();
      for (const row of matchingRows){
        const meta = row.metadata ?? {};
        const sectionId = String(meta["section_id"] ?? (Array.isArray(row.section_ids) ? row.section_ids[0] : "") ?? "").trim();
        const logicalKey = [
          row.report_name,
          sectionId,
          normalized(meta["breed_name"]),
          normalized(meta["club_name"]),
          normalized(meta["scope"]),
          normalized(meta["show_letter"])
        ].join("|");
        const existing = logicalArtifacts.get(logicalKey);
        const rowGeneration = Number(row.generation ?? 0);
        const existingGeneration = Number(existing?.generation ?? 0);
        const rowGeneratedAt = String(row.generated_at ?? "");
        const existingGeneratedAt = String(existing?.generated_at ?? "");
        if (!existing || rowGeneration > existingGeneration || rowGeneration === existingGeneration && rowGeneratedAt > existingGeneratedAt) {
          logicalArtifacts.set(logicalKey, row);
        }
      }
      if (logicalArtifacts.size > 0) {
        artifacts = [
          ...logicalArtifacts.values()
        ];
      }
    }
    for (const artifact of artifacts){
      if (artifact.artifact_status !== "generated") {
        return json({
          error: `Artifact ${artifact.id} is not generated yet.`
        }, 400);
      }
      if (!artifact.storage_bucket || !artifact.storage_path) {
        return json({
          error: `Artifact ${artifact.id} has no storage location.`
        }, 400);
      }
    }
    const { data: showRow, error: showError } = await adminClient.from("shows").select("id, name, owner_user_id, secretary_email").eq("id", showId).single();
    if (showError || !showRow) {
      return json({
        error: "Show not found."
      }, 404);
    }
    const replyTo = await replyToForShow(adminClient, showId, requestedReplyTo);
    const replyToList = emailList(replyTo);
    // BCC the show secretary or fallback show owner.
    const bccList = replyToList;
    const attachments = [];
    for (const artifact of artifacts){
      const storageBucket = artifact.storage_bucket;
      const storagePath = artifact.storage_path;
      if (!storageBucket || !storagePath) {
        return json({
          error: `Artifact ${artifact.id} has no storage location.`
        }, 400);
      }
      const { data: fileBytes, error: fileError } = await adminClient.storage.from(storageBucket).download(storagePath);
      if (fileError || !fileBytes) {
        return json({
          error: `Failed to download report file ${artifact.id}: ${fileError?.message ?? "unknown error"}`
        }, 500);
      }
      const arrayBuffer = await fileBytes.arrayBuffer();
      const base64Content = toBase64(new Uint8Array(arrayBuffer));
      const fileName = artifact.file_name?.trim() || `${artifact.report_name}.pdf`;
      attachments.push({
        filename: fileName,
        content: base64Content
      });
    }
    const artifactList = artifacts.map((artifact)=>{
      const meta = artifact.metadata ?? {};
      const scope = String(meta["scope"] ?? "").trim().toUpperCase();
      const showLetter = String(meta["show_letter"] ?? "").trim().toUpperCase();
      const sanctionNumber = String(meta["sanction_number"] ?? "").trim();
      const breedName = String(meta["breed_name"] ?? "").trim();
      const reportLabel = friendlyReportName(artifact.report_name);
      return {
        reportLabel,
        scope,
        showLetter,
        sanctionNumber,
        breedName,
        display: [
          reportLabel,
          scope,
          showLetter
        ].filter(Boolean).join(" - ")
      };
    });
    const includedSanctionNumbers = [
      ...new Set(artifactList.map((artifact)=>artifact.sanctionNumber).filter((value)=>value.length > 0))
    ];
    const breedNames = [
      ...new Set(artifactList.map((artifact)=>artifact.breedName).filter((value)=>value.length > 0))
    ];
    const fileListHtml = artifactList.map((artifact)=>`<li>${escapeHtml(artifact.display)}</li>`).join("");
    const subject = subjectOverride || `${showRow.name} - ${breedNames.length > 0 ? breedNames.join(", ") : "Club"} Club Reports`;
    const priorRecipient = recipients.join(", ");
    if (!forceResend) {
      const { data: priorDelivery, error: priorDeliveryError } = await adminClient.from("show_email_deliveries").select("id, provider_message_id, sent_at").eq("show_id", showId).eq("recipient_email", priorRecipient).eq("subject", subject).eq("delivery_status", "sent").order("sent_at", {
        ascending: false
      }).limit(1).maybeSingle();
      if (priorDeliveryError) {
        console.warn("Could not check prior report delivery", {
          show_id: showId,
          recipient_email: priorRecipient,
          subject,
          error: priorDeliveryError.message
        });
      } else if (priorDelivery) {
        return json({
          ok: true,
          message: "This breed report bundle was already sent.",
          already_sent: true,
          provider_message_id: priorDelivery.provider_message_id ?? null,
          sent_at: priorDelivery.sent_at ?? null,
          artifact_count: artifacts.length
        });
      }
    }
    const html = `
      <div style="font-family: Arial, sans-serif; line-height: 1.5;">
        <p>Hello,</p>

        <p>
          Attached are the sweepstakes and breed results detail reports for ${escapeHtml(showRow.name)}.
        </p>

        ${includedSanctionNumbers.length > 0 ? `
          <p>
            <strong>Included sections:</strong>
            ${escapeHtml(includedSanctionNumbers.join(", "))}
          </p>
        ` : ""}

        <p><strong>Attached files:</strong></p>

        <ul>
          ${fileListHtml}
        </ul>

        ${message ? `
          <div style="margin: 12px 0; white-space: pre-wrap;">
            ${escapeHtml(message)}
          </div>
        ` : ""}

        <p>
          Thank you,<br>
          RingMaster Show
        </p>
      </div>
    `;
    const resendPayload = {
      from: resendFromEmail,
      to: recipients,
      subject,
      html,
      attachments
    };
    if (replyToList) {
      resendPayload.reply_to = replyToList;
    }
    if (bccList) {
      resendPayload.bcc = bccList;
    }
    console.log("Sending club report email", {
      show_id: showId,
      user_id: user.id,
      to: resendPayload.to,
      subject: resendPayload.subject,
      reply_to: resendPayload.reply_to,
      bcc: resendPayload.bcc,
      artifact_count: artifacts.length
    });
    const idempotencySource = [
      showId,
      recipients.map((email)=>email.toLowerCase()).sort().join(","),
      subject.toLowerCase(),
      artifacts.map((artifact)=>artifact.id).sort().join(","),
      forceResend ? crypto.randomUUID() : ""
    ].join("|");
    const idempotencyKey = await sha256Hex(idempotencySource);
    const resendResp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": idempotencyKey
      },
      body: JSON.stringify(resendPayload)
    });
    let resendJson;
    try {
      resendJson = await resendResp.json();
    } catch  {
      resendJson = {
        error: "Resend returned a non-JSON response."
      };
    }
    let deliveryStatus = "sent";
    let deliveryError = null;
    let providerMessageId = null;
    if (!resendResp.ok) {
      deliveryStatus = "failed";
      deliveryError = JSON.stringify(resendJson);
      console.error("Resend report email failed", {
        status: resendResp.status,
        data: resendJson,
        to: resendPayload.to,
        reply_to: resendPayload.reply_to,
        bcc: resendPayload.bcc
      });
    } else {
      providerMessageId = typeof resendJson["id"] === "string" ? resendJson["id"] : null;
      console.log("Resend report email sent", {
        status: resendResp.status,
        id: providerMessageId,
        to: resendPayload.to,
        reply_to: resendPayload.reply_to,
        bcc: resendPayload.bcc
      });
    }
    const { error: logError } = await adminClient.from("show_email_deliveries").insert(artifacts.map((artifact)=>({
        show_id: showId,
        artifact_id: artifact.id,
        report_name: artifact.report_name,
        recipient_email: recipients.join(", "),
        recipient_name: null,
        subject,
        delivery_type: artifact.report_name,
        delivery_status: deliveryStatus,
        provider_message_id: providerMessageId,
        error_message: deliveryError,
        sent_at: deliveryStatus === "sent" ? new Date().toISOString() : null
      })));
    if (logError) {
      console.error("Email log insert failed", {
        show_id: showId,
        error: logError
      });
    }
    if (!resendResp.ok) {
      return json({
        error: "Email send failed",
        details: resendJson
      }, 500);
    }
    return json({
      ok: true,
      message: "Report email sent.",
      provider_message_id: providerMessageId,
      artifact_count: artifacts.length,
      reply_to: resendPayload.reply_to ?? null,
      bcc: resendPayload.bcc ?? null
    });
  } catch (err) {
    console.error("Unhandled send-club-report-email error", err);
    return json({
      error: err instanceof Error ? err.message : "Unknown error"
    }, 500);
  }
});
function cleanEmail(value) {
  const email = String(value ?? "").trim();
  return email.includes("@") ? email : "";
}
function emailList(value) {
  if (!value) return undefined;
  const values = Array.isArray(value) ? value : String(value).split(",");
  const emails = values.map((entry)=>cleanEmail(entry)).filter((email)=>email.length > 0);
  const uniqueEmails = [
    ...new Set(emails)
  ];
  return uniqueEmails.length > 0 ? uniqueEmails : undefined;
}
async function replyToForShow(adminClient, showId, requestedReplyTo) {
  const manualReplyTo = cleanEmail(requestedReplyTo);
  if (manualReplyTo) {
    return manualReplyTo;
  }
  const { data: show, error: showError } = await adminClient.from("shows").select("id, owner_user_id, secretary_email").eq("id", showId).maybeSingle();
  if (showError) {
    console.warn(`Could not load show reply-to info: ${showError.message}`);
    return "";
  }
  const secretaryEmail = cleanEmail(show?.secretary_email);
  if (secretaryEmail) {
    return secretaryEmail;
  }
  const ownerUserId = String(show?.owner_user_id ?? "").trim();
  if (ownerUserId) {
    const { data, error } = await adminClient.auth.admin.getUserById(ownerUserId);
    if (!error) {
      const ownerEmail = cleanEmail(data?.user?.email);
      if (ownerEmail) {
        return ownerEmail;
      }
    }
    console.warn(`Could not load owner email for show ${showId}: ${error?.message ?? "Unknown error"}`);
  }
  return "";
}
function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json"
    }
  });
}
function toBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for(let offset = 0; offset < bytes.length; offset += chunkSize){
    const chunk = bytes.subarray(offset, offset + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}
async function sha256Hex(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [
    ...new Uint8Array(digest)
  ].map((byte)=>byte.toString(16).padStart(2, "0")).join("");
}
function friendlyReportName(key) {
  switch(key){
    case "arba_report":
      return "ARBA Report";
    case "exhibitor_report":
      return "Exhibitor Report";
    case "legs":
      return "Leg Certificates";
    case "sweepstakes_report":
      return "Sweepstakes Report";
    case "breed_results_detail_report":
      return "Breed Results Detail Report";
    default:
      return key.split("_").map((word)=>word ? word[0].toUpperCase() + word.slice(1) : word).join(" ");
  }
}
function escapeHtml(input) {
  return input.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
}
