import { createClient } from "npm:@supabase/supabase-js@2.95.0";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { forwardHeaders, responseHeaders, route } from "./routes.ts";

const project = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const enc = new TextEncoder();
const key = crypto.subtle.digest(
  "SHA-256",
  enc.encode("rm/support/v1:" + Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!),
)
  .then((raw) =>
    crypto.subtle.importKey("raw", raw, "AES-GCM", false, [
      "encrypt",
      "decrypt",
    ])
  );
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Methods":
    "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": [
    "authorization",
    "apikey",
    "x-client-info",
    "x-rm-session",
    ...forwardHeaders,
  ].join(", "),
  "Access-Control-Expose-Headers": responseHeaders.join(", "),
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
function decodeJwt(token: string) {
  return JSON.parse(
    atob(token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/")),
  );
}
async function seal(id: string, token: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const bytes = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData: enc.encode(id) },
      await key,
      enc.encode(token),
    ),
  );
  return btoa(String.fromCharCode(...iv, ...bytes));
}
async function open(id: string, sealed: string) {
  const b = Uint8Array.from(atob(sealed), (c) => c.charCodeAt(0));
  return new TextDecoder().decode(
    await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: b.slice(0, 12), additionalData: enc.encode(id) },
      await key,
      b.slice(12),
    ),
  );
}
type DisplayAccount = {
  id: string;
  email?: string;
  created_at: string;
  user_metadata?: Record<string, unknown>;
};
function workspace(
  id: string,
  expiresAt: string,
  token: string,
  user: DisplayAccount,
) {
  const meta = user.user_metadata ?? {};
  return json({
    id,
    expires_at: Math.min(Date.parse(expiresAt) / 1000, decodeJwt(token).exp),
    user: {
      id: user.id,
      email: user.email,
      aud: "authenticated",
      role: "authenticated",
      created_at: user.created_at,
      app_metadata: {},
      user_metadata: {
        display_name: meta.display_name,
        full_name: meta.full_name,
        name: meta.name,
      },
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const { user: actor } = await authenticatedUser(req);
    // Claim belongs to the token just verified by Auth, not a caller-supplied actor.
    const claims = decodeJwt(req.headers.get("Authorization")!.split(/\s+/)[1]);
    if (
      actor.factors?.some((f) => f.status === "verified") &&
      claims.aal !== "aal2"
    ) {
      return json({
        error: "Complete administrator MFA before starting Support Mode.",
      }, 403);
    }
    const actorSession = claims.session_id;
    if (!actorSession) {
      return json({ error: "Sign in again to start Support Mode." }, 403);
    }
    const db = serviceClient();
    const manage = async (action: string, params: Record<string, unknown>) => {
      const { data, error } = await db.rpc("manage_support_session", {
        p_action: action,
        p_actor: actor.id,
        p_actor_session: actorSession,
        ...params,
      });
      if (error) {
        throw new Error(
          error.code === "42501"
            ? error.message
            : "Support session unavailable.",
        );
      }
      return data;
    };
    const url = new URL(req.url);
    const prefix = "/support-session/proxy/";
    const idx = url.pathname.indexOf(prefix);
    if (idx >= 0) {
      const path = url.pathname.slice(idx + prefix.length - 1);
      const resource = route(path);
      if (!resource) {
        return json({ error: "Unsupported support request." }, 403);
      }
      if (
        resource === "table/profiles" &&
        ["POST", "PATCH", "PUT"].includes(req.method)
      ) {
        const payload = await req.clone().json();
        const rows = Array.isArray(payload) ? payload : [payload];
        if (
          rows.some((row) =>
            Object.keys(row ?? {}).some((k) =>
              /^accepted_(terms|privacy)_/.test(k)
            )
          )
        ) {
          return json({
            error:
              "Agreement acceptance must be completed by the account holder.",
          }, 403);
        }
      }
      const session = await manage("request", {
        p_session: req.headers.get("x-rm-session"),
        p_method: req.method,
        p_resource: resource,
      });
      const token = await open(session.id, session.sealed);
      const headers = new Headers({
        Authorization: "Bearer " + token,
        apikey: anon,
      });
      for (const h of forwardHeaders) {
        if (req.headers.has(h)) headers.set(h, req.headers.get(h)!);
      }
      const dest = new URL(project);
      dest.pathname = path;
      dest.search = url.search;
      if (resource === "partner/breeder-refresh") {
        if (req.method !== "POST") {
          return json({ error: "Invalid partner request." }, 405);
        }
        // Same first-party Breeder endpoint used by the ordinary Show client.
        const body = await req.json();
        if (body.action !== "pull" || typeof body.owner_id !== "string") {
          return json({ error: "Invalid refresh." }, 400);
        }
        const partner = await fetch(
          "https://aqfsrolvaewcpkdkttiz.supabase.co/functions/v1/show-connection",
          {
            method: "POST",
            redirect: "error",
            headers: {
              Authorization: "Bearer " + token,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ action: "pull", owner_id: body.owner_id }),
          },
        );
        return new Response(partner.body, {
          status: partner.status,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
      const out = await fetch(dest, {
        method: req.method,
        headers,
        redirect: "manual",
        body: ["GET", "HEAD"].includes(req.method) ? undefined : req.body,
      });
      if (out.status >= 300 && out.status < 400) {
        return json({ error: "Unexpected service redirect." }, 502);
      }
      const returned = new Headers(cors);
      for (const h of responseHeaders) {
        if (out.headers.has(h)) returned.set(h, out.headers.get(h)!);
      }
      return new Response(out.body, { status: out.status, headers: returned });
    }
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }
    const body = await req.json();
    if (body.action === "end") {
      const s = await manage("end", { p_session: body.session_id });
      if (s.sealed) {
        await db.auth.admin.signOut(await open(s.id, s.sealed), "local");
      }
      return json({ ok: true });
    }
    if (body.action === "resume") {
      const s = await manage("request", {
        p_session: body.session_id,
        p_method: "GET",
        p_resource: "session/resume",
      });
      const token = await open(s.id, s.sealed);
      const { data, error } = await db.auth.getUser(token);
      if (error || data.user?.id !== s.target) {
        return json({ error: "Support session expired." }, 403);
      }
      return workspace(s.id, s.expires_at, token, data.user);
    }
    if (body.action !== "start") return json({ error: "Invalid action." }, 400);
    const s = await manage("start", { p_target: body.target_id });
    if (s.mode === "preview") return json({ mode: "preview" });
    let access: string | undefined;
    try {
      // Create a separate server-side Auth session for an existing VERIFIED
      // account. generateLink does not send mail. No link, OTP, refresh token
      // or usable target JWT is returned to the administrator's browser.
      const { data: account, error: lookup } = await db.auth.admin.getUserById(
        s.target,
      );
      if (lookup || !account.user?.email || !account.user.email_confirmed_at) {
        throw new Error();
      }
      const { data: link, error: linkError } = await db.auth.admin.generateLink(
        { type: "magiclink", email: account.user.email },
      );
      if (
        linkError || link.user?.id !== s.target ||
        !link.properties?.hashed_token
      ) throw new Error();
      const verifier = createClient(project, anon, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await verifier.auth.verifyOtp({
        token_hash: link.properties.hashed_token,
        type: "email",
      });
      if (error || !data.session) throw new Error();
      access = data.session.access_token;
      if (data.user?.id !== s.target) throw new Error();
      await manage("activate", {
        p_session: s.id,
        p_sealed: await seal(s.id, access),
        p_target_session: decodeJwt(access).session_id,
      });
      return workspace(s.id, s.expires_at, access, account.user);
    } catch {
      await manage("end", { p_session: s.id });
      if (access) await db.auth.admin.signOut(access, "local");
      return json({ error: "Could not open a verified support session." }, 403);
    }
  } catch (error) {
    const msg = error instanceof Error ? error.message : "";
    return json({
      error: msg.startsWith("Support session ended")
        ? msg
        : "Support request denied.",
    }, 403);
  }
});
