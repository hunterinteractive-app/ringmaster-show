// @ts-nocheck
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sweepstakes.ringmasterone.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
const normalized = (value: unknown) => String(value ?? "").trim().toLowerCase();

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const origin = request.headers.get("origin");
  if (origin && origin !== "https://sweepstakes.ringmasterone.com" && !origin.startsWith("http://localhost:")) return json({ error: "Not allowed" }, 403);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authHeader = request.headers.get("Authorization") ?? "";
  if (!supabaseUrl || !anonKey || !serviceRole || !authHeader) return json({ error: "Unauthorized" }, 401);

  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(supabaseUrl, serviceRole, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) return json({ error: "Unauthorized" }, 401);

  const body = await request.json().catch(() => ({}));
  const showId = String(body.show_id ?? "").trim();
  const portalClubId = String(body.portal_club_id ?? "").trim();
  const sanctionNumber = String(body.sanction_number ?? "").trim();
  if (!showId || !portalClubId) return json({ error: "Report details are missing." }, 400);

  // This RPC is the authorization boundary: it only returns rows assigned to
  // the signed-in chair (or the designated tester preview account).
  const { data: visibleRows, error: visibleError } = await userClient.rpc("list_sweepstakes_portal_shows");
  if (visibleError) return json({ error: "We could not confirm portal access." }, 403);
  const visible = (visibleRows ?? []).find((row: any) =>
    String(row.portal_club_id) === portalClubId && String(row.show_id) === showId && String(row.sanction_number ?? "") === sanctionNumber && row.report_status === "generated"
  );
  if (!visible) return json({ error: "That report is not available to this portal account." }, 403);

  const clubName = String(visible.club_name ?? "");
  const bodyName = String(visible.sanctioning_body ?? "").trim().toUpperCase();
  const isArba = normalized(clubName) === "arba";
  const { data: artifacts, error: artifactError } = await admin
    .from("show_report_artifacts")
    .select("id, report_name, artifact_status, storage_bucket, storage_path, file_name, metadata, generated_at")
    .eq("show_id", showId)
    .eq("is_current", true)
    .in("artifact_status", isArba ? ["generated", "warning"] : ["generated"]);
  if (artifactError) return json({ error: "We could not locate the report files." }, 500);

  const matching = (artifacts ?? []).filter((artifact: any) => {
    const meta = artifact.metadata ?? {};
    if (!artifact.storage_bucket || !artifact.storage_path) return false;
    if (isArba) return artifact.report_name === "arba_report" && String(artifact.id) === String(visible.report_artifact_id);
    if (normalized(meta.club_name) !== normalized(clubName)) return false;
    if (bodyName === "STATE CLUB") {
      if (!["details_by_breed", "exh_by_breed", "best_display_report"].includes(artifact.report_name)) return false;
      return String(meta.sanction_number ?? sanctionNumber) === sanctionNumber;
    }
    if (!["sweepstakes_report", "breed_results_detail_report", "details_by_breed", "exh_by_breed"].includes(artifact.report_name)) return false;
    return String(meta.sanction_number ?? "") === sanctionNumber;
  }).sort((a: any, b: any) => String(a.report_name).localeCompare(String(b.report_name)));

  if (!matching.length) return json({ error: "The report files are still being prepared." }, 409);
  const downloads = [];
  for (const artifact of matching) {
    const { data, error } = await admin.storage.from(artifact.storage_bucket).createSignedUrl(artifact.storage_path, 60, { download: artifact.file_name || `${artifact.report_name}.pdf` });
    if (error || !data?.signedUrl) return json({ error: "We could not prepare the report download." }, 500);
    downloads.push({ name: artifact.file_name || `${artifact.report_name}.pdf`, url: data.signedUrl });
  }
  return json({ downloads });
});
