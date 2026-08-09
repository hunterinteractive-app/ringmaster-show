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
  const { data: visibleRows, error: visibleError } = await userClient.rpc("get_sweepstakes_portal_shows_payload");
  if (visibleError) return json({ error: "We could not confirm portal access." }, 403);
  const visible = (visibleRows ?? []).find((row: any) =>
    String(row.portal_club_id) === portalClubId && String(row.show_id) === showId && String(row.sanction_number ?? "") === sanctionNumber
  );
  if (!visible) return json({ error: "That report is not available to this portal account." }, 403);

  const clubName = String(visible.club_name ?? "");
  const bodyName = String(visible.sanctioning_body ?? "").trim().toUpperCase();
  const sectionLabel = normalized(visible.section_label);
  const isArba = normalized(clubName) === "arba";
  const { data: artifacts, error: artifactError } = await admin
    .from("show_report_artifacts")
    .select("id, finalize_run_id, scope_key, section_ids, report_name, artifact_status, storage_bucket, storage_path, file_name, metadata, generated_at")
    .eq("show_id", showId)
    .eq("is_current", true);
  if (artifactError) return json({ error: "We could not locate the report files." }, 500);

  const matching = (artifacts ?? []).filter((artifact: any) => {
    const meta = artifact.metadata ?? {};
    // A sanction can be blank or shared by several sections (notably state
    // club reports). In that case the report's structured section label is the
    // boundary that keeps one portal row from refreshing every section.
    const sectionMatches = !sectionLabel ||
      !meta.section_label ||
      normalized(meta.section_label) === sectionLabel;
    if (isArba) return artifact.report_name === "arba_report" && String(artifact.id) === String(visible.report_artifact_id);
    if (normalized(meta.club_name) !== normalized(clubName)) return false;
    if (bodyName === "STATE CLUB") {
      if (!["details_by_breed", "exh_by_breed", "best_display_report"].includes(artifact.report_name)) return false;
      return String(meta.sanction_number ?? sanctionNumber) === sanctionNumber && sectionMatches;
    }
    if (!["sweepstakes_report", "breed_results_detail_report", "details_by_breed", "exh_by_breed"].includes(artifact.report_name)) return false;
    return String(meta.sanction_number ?? "") === sanctionNumber && sectionMatches;
  }).sort((a: any, b: any) => String(a.report_name).localeCompare(String(b.report_name)));

  if (!matching.length) return json({ error: "The report files are still being prepared." }, 409);
  const isReady = (artifact: any) =>
    artifact.artifact_status === "generated" ||
    (isArba && artifact.artifact_status === "warning");

  // A download is also the portal's freshness check.  It queues a new render
  // only when report-relevant data changed after this exact artifact was made;
  // otherwise it immediately returns the existing PDF(s).
  const reportInputsChangedSince = async (artifact: any) => {
    if (!artifact.generated_at) return true;
    const sectionIds = Array.isArray(artifact.section_ids) ? artifact.section_ids : [];
    const timestamps: string[] = [];
    const addTimestamp = (value: unknown) => {
      if (value && !Number.isNaN(new Date(String(value)).getTime())) timestamps.push(String(value));
    };

    const [{ data: show }, { data: sanction }, { data: latestEntry }] = await Promise.all([
      admin.from("shows").select("updated_at, results_last_changed_at").eq("id", showId).maybeSingle(),
      admin.from("show_sanctions").select("updated_at").eq("show_id", showId).order("updated_at", { ascending: false }).limit(1).maybeSingle(),
      sectionIds.length
        ? admin.from("entries").select("updated_at").eq("show_id", showId).in("section_id", sectionIds).order("updated_at", { ascending: false }).limit(1).maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    addTimestamp(show?.updated_at);
    addTimestamp(show?.results_last_changed_at);
    addTimestamp(sanction?.updated_at);
    addTimestamp(latestEntry?.updated_at);
    const newestInput = timestamps.reduce<number>((latest, value) => Math.max(latest, new Date(value).getTime()), 0);
    return newestInput > new Date(artifact.generated_at).getTime();
  };

  // The portal only exposes an aggregate of its own authorized report jobs.
  // Queue timestamps let the chair see whether the renderer is actively working
  // instead of being left with an indeterminate "Preparing" state.
  const getProgress = async (currentArtifacts: any[]) => {
    const artifactIds = currentArtifacts.map((artifact: any) => artifact.id);
    const { data: tasks, error: taskError } = await admin
      .from("show_task_queue")
      .select("report_artifact_id, task_status, created_at, started_at, heartbeat_at, available_at")
      .eq("task_type", "render_report")
      .in("report_artifact_id", artifactIds)
      .order("created_at", { ascending: false });
    if (taskError) {
      console.error("Could not load Sweepstakes report progress", taskError);
    }

    const latestTaskByArtifact = new Map<string, any>();
    for (const task of tasks ?? []) {
      const artifactId = String(task.report_artifact_id ?? "");
      if (artifactId && !latestTaskByArtifact.has(artifactId)) {
        latestTaskByArtifact.set(artifactId, task);
      }
    }
    const now = Date.now();
    const pending = currentArtifacts.filter((artifact: any) => {
      const taskStatus = String(
        latestTaskByArtifact.get(String(artifact.id))?.task_status ?? "",
      );
      return !isReady(artifact) || ["queued", "running"].includes(taskStatus);
    });
    const stalled = pending.some((artifact: any) => {
      const task = latestTaskByArtifact.get(String(artifact.id));
      if (!task) return false;
      const taskStatus = String(task.task_status ?? "");
      const lastActivity = task.heartbeat_at ?? task.started_at ?? task.available_at ?? task.created_at;
      const age = lastActivity ? now - new Date(lastActivity).getTime() : 0;
      return (taskStatus === "running" && age > 75_000) ||
        (taskStatus === "queued" && age > 120_000);
    });
    const hasRunningTask = pending.some((artifact: any) =>
      String(latestTaskByArtifact.get(String(artifact.id))?.task_status ?? "") === "running",
    );
    return {
      completed: currentArtifacts.length - pending.length,
      total: currentArtifacts.length,
      phase: stalled ? "stalled" : hasRunningTask ? "rendering" : "queued",
      // A deliberately conservative estimate: report rendering normally takes
      // about 25 seconds per remaining file, plus a short queue hand-off.
      estimated_seconds_remaining: stalled ? null : Math.max(15, pending.length * 25),
    };
  };

  // Queue only those report files whose inputs are newer than their generated
  // version. This preserves instant downloads when nothing has changed.
  if (matching.every(isReady)) {
    const staleArtifacts = (await Promise.all(matching.map(async (artifact: any) =>
      (await reportInputsChangedSince(artifact)) ? artifact : null,
    ))).filter(Boolean);
    if (staleArtifacts.length) {
      const refreshes = await Promise.all(staleArtifacts.map((artifact: any) =>
        admin.rpc("requeue_single_closeout_artifact", {
          p_show_id: showId,
          p_finalize_run_id: artifact.finalize_run_id,
          p_scope_key: artifact.scope_key,
          p_artifact_id: artifact.id,
        }),
      ));
      const refreshError = refreshes.find((result: any) => result.error)?.error;
      if (refreshError) {
        console.error("Could not queue a fresh Sweepstakes report", refreshError);
        return json({ error: "We could not queue the latest report files." }, 500);
      }
      return json({ refreshing: true, retry_after_ms: 2000, progress: await getProgress(matching) }, 202);
    }
  }

  if (!matching.every(isReady)) {
    const hasFailure = matching.some((artifact: any) => artifact.artifact_status === "failed");
    return json(
      hasFailure
        ? { error: "The latest report could not be prepared. Please try again shortly." }
        : { refreshing: true, retry_after_ms: 2000, progress: await getProgress(matching) },
      hasFailure ? 500 : 202,
    );
  }

  if (matching.some((artifact: any) => !artifact.storage_bucket || !artifact.storage_path)) {
    return json({ error: "The refreshed report files are still being saved." }, 409);
  }
  const downloads = [];
  for (const artifact of matching) {
    const name = artifact.file_name || `${artifact.report_name}.pdf`;
    const [{ data: download, error: downloadError }, { data: view, error: viewError }] = await Promise.all([
      admin.storage.from(artifact.storage_bucket).createSignedUrl(artifact.storage_path, 60, { download: name }),
      admin.storage.from(artifact.storage_bucket).createSignedUrl(artifact.storage_path, 60),
    ]);
    if (downloadError || viewError || !download?.signedUrl || !view?.signedUrl) return json({ error: "We could not prepare the report files." }, 500);
    downloads.push({ name, url: download.signedUrl, view_url: view.signedUrl });
  }
  return json({ downloads });
});
