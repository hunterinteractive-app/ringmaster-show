import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let jobId: string | null = null;
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authorization = req.headers.get("Authorization") ?? "";
  const supabase = createClient(url, serviceKey);

  try {
    const token = authorization.replace(/^Bearer\s+/i, "").trim();
    const { data: authData, error: authError } = await supabase.auth.getUser(
      token,
    );
    if (authError || !authData.user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const body = await req.json();
    const showId = String(body.show_id ?? "").trim();
    const scopeLabel = String(body.scope_label ?? "Selected Scope").trim();
    const suppliedScopeKey = String(body.scope_key ?? "").trim();
    const sectionIds = Array.isArray(body.section_ids)
      ? Array.from(
        new Set(
          body.section_ids.map((id: unknown) => String(id).trim()).filter(
            Boolean,
          ),
        ),
      ).sort()
      : [];

    if (!showId || sectionIds.length === 0) {
      return json(
        { error: "show_id and at least one section_id are required" },
        400,
      );
    }

    const stableScopeKey = `${showId}:${sectionIds.join(",")}`;
    if (suppliedScopeKey && suppliedScopeKey !== stableScopeKey) {
      return json({ error: "scope_key does not match section_ids" }, 400);
    }

    const { data: allowed, error: permissionError } = await supabase.rpc(
      "user_can_finalize_show",
      { p_show_id: showId, p_user_id: authData.user.id },
    );
    if (permissionError) throw permissionError;
    if (allowed !== true) {
      return json({ error: "You cannot finalize this show" }, 403);
    }

    const { data: job, error: jobError } = await supabase.from("closeout_jobs")
      .insert({
        show_id: showId,
        status: "running",
        step: "starting",
        started_at: new Date().toISOString(),
      })
      .select("id").single();
    if (jobError) throw jobError;
    jobId = String(job.id);

    const updateStep = (step: string) =>
      supabase.from("closeout_jobs").update({ step }).eq("id", jobId!);
    await updateStep(`finalizing ${scopeLabel}`);

    const { data: finalizeRunId, error: finalizeError } = await supabase.rpc(
      "finalize_show_scoped",
      {
        p_show_id: showId,
        p_section_ids: sectionIds,
        p_scope_label: scopeLabel,
        p_scope_key: stableScopeKey,
      },
    );
    if (finalizeError) throw finalizeError;

    await supabase.from("closeout_jobs").update({
      status: "complete",
      step: "complete",
      finished_at: new Date().toISOString(),
    }).eq("id", jobId);

    return json({
      ok: true,
      job_id: jobId,
      finalize_run_id: finalizeRunId,
      scope_key: stableScopeKey,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (jobId) {
      await supabase.from("closeout_jobs").update({
        status: "failed",
        step: "failed",
        error_message: message,
        finished_at: new Date().toISOString(),
      }).eq("id", jobId);
    }
    console.error("run-closeout failed", { jobId, message });
    return json({ error: message }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
