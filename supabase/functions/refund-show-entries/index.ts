import {
  authenticatedUser,
  isServiceRoleRequest,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  EntryRefund,
  processEntryRefund,
} from "../_shared/entry_refund_processor.ts";
import {
  squareRefundProvider,
  stripeRefundProvider,
} from "../_shared/entry_refund_providers.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function isReconciler(request: Request): Promise<boolean> {
  const expected = Deno.env.get("ENTRY_REFUND_RECONCILE_SECRET") ?? "";
  const supplied = (request.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  if (!expected || !supplied) return false;
  const hashes = await Promise.all(
    [supplied, expected].map((s) =>
      crypto.subtle.digest("SHA-256", new TextEncoder().encode(s))
    ),
  );
  const [actual, wanted] = hashes.map((h) => new Uint8Array(h));
  let difference = 0;
  for (let i = 0; i < wanted.length; i++) difference |= actual[i] ^ wanted[i];
  return difference === 0;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: cors });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const backend = serviceClient();
  async function rpc(name: string, args: Record<string, unknown>) {
    const { data, error } = await backend.rpc(name, args);
    if (error) throw new Error(error.message);
    return data;
  }
  async function run(item: EntryRefund) {
    const current = await rpc("mark_entry_refund_attempt", {
      p_id: item.id,
    }) as EntryRefund;
    return processEntryRefund(
      current,
      current.provider === "square"
        ? squareRefundProvider(backend)
        : stripeRefundProvider(),
      (status, reference, error) =>
        rpc("finish_entry_refund", {
          p_id: item.id,
          p_status: status,
          p_provider_refund_id: reference,
          p_error: error,
        }),
    );
  }
  try {
    const body = await request.json();
    if (
      body.action === "reconcile" &&
      (await isReconciler(request) || await isServiceRoleRequest(request))
    ) {
      const work = await rpc("get_entry_refund_work", {}) as EntryRefund[];
      const results = [];
      // A provider failure must not starve other requests in this batch.
      for (const item of work) {
        try {
          results.push(await run(item));
        } catch {
          results.push({ id: item.id, status: "retry_needed" });
        }
      }
      return json({ results });
    }
    const { user, client } = await authenticatedUser(request);
    if (!uuid.test(String(body.request_id ?? ""))) {
      return json({ error: "A valid refund request ID is required." }, 400);
    }
    if (body.action === "status") {
      const work = await rpc("get_entry_refund_work", {
        p_id: body.request_id,
      }) as EntryRefund[];
      if (!work.length) return json({ error: "Refund not found." }, 404);
      const { data, error } = await client.rpc("can_refund_show_entries", {
        p_show_id: work[0].show_id,
      });
      if (error || data !== true) {
        return json({
          error: "Only show secretaries and administrators can manage refunds.",
        }, 403);
      }
      return json(await run(work[0]));
    }
    if (body.action !== "refund") {
      return json({ error: "Invalid action." }, 400);
    }
    if (
      !uuid.test(String(body.payment_id ?? "")) ||
      !Array.isArray(body.entry_ids) ||
      body.entry_ids.length < 1 || body.entry_ids.length > 500 ||
      body.entry_ids.some((id: unknown) => !uuid.test(String(id))) ||
      !Number.isSafeInteger(body.entry_amount_cents) ||
      !Number.isSafeInteger(body.online_fee_cents) ||
      typeof body.reason !== "string"
    ) {
      return json(
        { error: "Select entries, a valid amount, and a reason." },
        400,
      );
    }
    const item = await rpc("prepare_entry_refund", {
      p_id: body.request_id,
      p_actor: user.id,
      p_payment: body.payment_id,
      p_entry_ids: body.entry_ids,
      p_entry_amount: body.entry_amount_cents,
      p_online_fee: body.online_fee_cents,
      p_reason: body.reason,
      p_manual_returned: body.manual_returned === true,
    }) as EntryRefund;
    return json(await run(item));
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : "Refund could not be confirmed. Check its status before retrying.";
    return json(
      { error: message },
      message === "Authentication required." ? 401 : 400,
    );
  }
});
