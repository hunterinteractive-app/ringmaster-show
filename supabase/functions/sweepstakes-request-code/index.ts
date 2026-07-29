// @ts-nocheck
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sweepstakes.ringmasterone.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function emailHtml(code: string) {
  return `<!doctype html><html><body style="margin:0;padding:0;background:#f5f7f9;font-family:Arial,Helvetica,sans-serif;color:#1e2849"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:32px 16px"><tr><td align="center"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:620px;background:#fff;border:1px solid #dfe3e8;border-radius:16px;overflow:hidden"><tr><td style="padding:20px 28px;border-bottom:1px solid #dfe3e8"><strong style="font-size:20px">RingMaster Sweepstakes Portal</strong><br><span style="font-size:13px;color:#6b7280">A RingMaster One service</span></td></tr><tr><td style="padding:36px 28px"><h1 style="margin:0 0 12px;font-size:30px">Your sign-in code</h1><p style="font-size:16px;line-height:1.6;color:#4b5563">Use this secure six-digit code to access your club's Sweepstakes reports, sanctioned shows, and points settings.</p><div style="margin:24px 0;padding:18px 12px;background:#f3effa;border:1px solid #d9cfee;border-radius:12px;text-align:center;font-size:34px;font-weight:700;letter-spacing:8px;color:#391c77">${code}</div><p style="font-size:14px;line-height:1.7;color:#6b7280">This code can only be used once and expires soon. Do not share it with anyone.</p><p style="font-size:14px;line-height:1.7;color:#6b7280">If you did not request this email, you can safely ignore it.</p></td></tr><tr><td style="padding:20px 28px 28px;color:#6b7280;font-size:13px">RingMaster Sweepstakes Portal<br>sweepstakes.ringmasterone.com</td></tr></table></td></tr></table></body></html>`;
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return response({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "";
  if (!supabaseUrl || !serviceRole || !resendApiKey || !resendFromEmail) return response({ error: "Portal email is not configured." }, 500);

  const origin = request.headers.get("origin");
  if (origin && origin !== "https://sweepstakes.ringmasterone.com" && !origin.startsWith("http://localhost:")) return response({ error: "Not allowed" }, 403);
  const { email } = await request.json().catch(() => ({}));
  const normalizedEmail = typeof email === "string" ? email.trim().toLowerCase() : "";
  if (!/^\S+@\S+\.\S+$/.test(normalizedEmail)) return response({ error: "Enter a valid email address." }, 400);

  const admin = createClient(supabaseUrl, serviceRole, { auth: { autoRefreshToken: false, persistSession: false } });
  const [{ data: assignment }, { data: tester }] = await Promise.all([
    admin.from("sweepstakes_portal_assignments").select("id").eq("normalized_email", normalizedEmail).eq("is_active", true).limit(1).maybeSingle(),
    admin.from("sweepstakes_portal_testers").select("id").eq("normalized_email", normalizedEmail).eq("is_active", true).limit(1).maybeSingle(),
  ]);
  if (!assignment && !tester) return response({ ok: true });

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: "magiclink", email: normalizedEmail });
  const code = link?.properties?.email_otp;
  if (linkError || !code) { console.error("Could not generate Sweepstakes OTP", linkError); return response({ error: "We could not create a sign-in code. Please try again." }, 500); }

  const resendResponse = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${resendApiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: resendFromEmail, to: [normalizedEmail], subject: "Your RingMaster Sweepstakes Portal sign-in code", html: emailHtml(code) }),
  });
  if (!resendResponse.ok) { console.error("Resend failed", await resendResponse.text()); return response({ error: "We could not send the code. Please try again." }, 502); }
  return response({ ok: true, verification_type: link.properties.verification_type ?? "magiclink" });
});
