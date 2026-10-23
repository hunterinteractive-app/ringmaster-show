import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createReportDownloadHandler } from "./handler.ts";
import { JWT } from "npm:google-auth-library@11.3.1";
import { createWorkerTrigger } from "./worker-trigger.ts";

declare const EdgeRuntime: { waitUntil(task: Promise<void>): void };
let workerAuth: JWT | undefined;
const triggerWorker = createWorkerTrigger({
  workerUrl: Deno.env.get("CLOSEOUT_WORKER_URL") ?? "",
  workToken: Deno.env.get("CLOSEOUT_WORKER_TRIGGER_TOKEN") ?? "",
  waitUntil: (task) => EdgeRuntime.waitUntil(task),
  onFailure: () => console.warn("Report worker wake-up failed; scheduled backup will retry"),
  getIdentityToken: async (audience) => {
    if (!workerAuth) {
      const credentials = JSON.parse(Deno.env.get("CLOSEOUT_WORKER_GOOGLE_CREDENTIALS") ?? "{}");
      if (!credentials.client_email || !credentials.private_key) {
        throw new Error("Worker credentials are not configured");
      }
      workerAuth = new JWT({
        email: credentials.client_email,
        key: credentials.private_key,
        transporterOptions: { timeout: 5000, retry: false },
      });
    }
    return await workerAuth.fetchIdToken(audience);
  },
});

serve(createReportDownloadHandler({
  createClient,
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  serviceRole: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  triggerWorker,
}));
