// @ts-nocheck
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!authHeader || !supabaseUrl || !supabaseAnonKey) {
    return json({ error: "Missing authenticated Supabase function context." }, 401);
  }

  try {
    const body = await req.json();
    const showId = String(body.show_id ?? "").trim();
    const deliveries = Array.isArray(body.deliveries) ? body.deliveries : [];
    if (!showId || deliveries.length === 0) {
      return json({ error: "show_id and deliveries are required." }, 400);
    }

    const results = [];
    const batchSize = 4;
    for (let start = 0; start < deliveries.length; start += batchSize) {
      const batch = deliveries.slice(start, start + batchSize);
      const outcomes = await Promise.all(batch.map(async (delivery) => {
        const response = await fetch(`${supabaseUrl}/functions/v1/send-report-email`, {
          method: "POST",
          headers: {
            "Authorization": authHeader,
            "apikey": supabaseAnonKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            show_id: showId,
            artifact_ids: delivery.artifact_ids,
            to: delivery.to,
            subject: delivery.subject,
            message: delivery.message,
          }),
        });
        const data = await response.json().catch(() => ({}));
        return {
          to: delivery.to,
          ok: response.ok && data?.ok === true,
          already_sent: data?.already_sent === true,
          error: data?.error ?? data?.message ?? null,
        };
      }));
      results.push(...outcomes);
    }

    const sentCount = results.filter((result) => result.ok && !result.already_sent).length;
    const alreadySentCount = results.filter((result) => result.ok && result.already_sent).length;
    const failures = results.filter((result) => !result.ok);
    return json({
      ok: true,
      sent_count: sentCount,
      already_sent_count: alreadySentCount,
      failed_count: failures.length,
      failures: failures.map(({ to, error }) => ({ to, error })),
    });
  } catch (error) {
    console.error("Club report batch failed", error);
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});
