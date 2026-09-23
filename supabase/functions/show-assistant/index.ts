import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  answerQuestion,
  MAX_BODY_BYTES,
  parseRequest,
  providerBody,
  unavailableMessages,
} from "./core.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  let requestId: string | undefined;
  let inputTokens = 0;
  let outputTokens = 0;
  let calls = 0;
  let reserved = false;
  try {
    const { user, client } = await authenticatedUser(request);
    if (user.is_anonymous) {
      return jsonResponse({
        answer: "Sign in with your RingMaster account to use AI help.",
        unavailable: true,
      }, 403);
    }
    // Read a bounded stream, including when Content-Length is omitted or forged.
    const reader = request.body?.getReader();
    if (!reader) throw new Error("invalid_request");
    let size = 0;
    const chunks: Uint8Array[] = [];
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_BODY_BYTES) {
        await reader.cancel();
        throw new Error("invalid_request");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const c of chunks) {
      bytes.set(c, offset);
      offset += c.length;
    }
    const b = parseRequest(JSON.parse(new TextDecoder().decode(bytes)));
    requestId = b.requestId;
    const key = Deno.env.get("OPENAI_API_KEY");
    if (!key) {
      return jsonResponse({
        answer: unavailableMessages.paused,
        unavailable: true,
      });
    }
    // Check scope BEFORE spending. The AI has no service client or actor argument.
    const owner = b.ownerId || user.id;
    if (["entries", "reports", "household"].includes(b.topic)) {
      const r = await client.rpc("can_access_household", {
        p_owner_user_id: owner,
      });
      if (r.error || r.data !== true) {
        return jsonResponse({
          answer:
            "That household is unavailable. Select your own household or contact support.",
          unavailable: true,
        }, 403);
      }
    }
    if (["setup", "closeout"].includes(b.topic) && b.showId) {
      const r = await client.rpc("user_can_manage_show_settings", {
        p_show_id: b.showId,
        p_user_id: user.id,
      });
      if (r.error || r.data !== true) {
        return jsonResponse({
          answer: "You do not have secretary access to that show.",
          unavailable: true,
        }, 403);
      }
    }
    if (!["help", "household"].includes(b.topic) && !b.showId) {
      return jsonResponse({
        answer:
          "Select a show so I can check the information relevant to your question.",
        unavailable: true,
      });
    }
    const input: unknown[] = [...b.history, {
      role: "user",
      content:
        `Selected topic: ${b.topic}. Screen: ${b.page}.\nQuestion: ${b.message}`,
    }];
    providerBody(input, b.topic !== "help"); // reject oversized requests before reservation
    const meter = serviceClient();
    const reservation = await meter.rpc("assistant_reserve", {
      p_actor: user.id,
      p_request: b.requestId,
      p_conversation: b.conversationId,
      p_topic: b.topic,
    });
    if (reservation.error) throw new Error("meter_unavailable");
    if (reservation.data?.allowed !== true) {
      return jsonResponse({
        answer: unavailableMessages[reservation.data?.reason] ||
          unavailableMessages.paused,
        unavailable: true,
      });
    }
    reserved = true;
    async function ask(body: unknown) {
      calls++;
      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${key}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(25000),
      });
      if (!response.ok) throw new Error("provider_unavailable");
      const r = await response.json();
      if (
        !Number.isSafeInteger(r.usage?.input_tokens) ||
        !Number.isSafeInteger(r.usage?.output_tokens) ||
        r.usage.input_tokens < 0 || r.usage.output_tokens < 0
      ) throw new Error("usage_unavailable");
      inputTokens += r.usage.input_tokens;
      outputTokens += r.usage.output_tokens;
      if (r.status !== "completed" || !Array.isArray(r.output)) {
        throw new Error("incomplete_response");
      }
      return r;
    }
    const { answer, checked } = await answerQuestion(
      input,
      b.topic !== "help",
      ask,
      async () => {
        const facts = await client.rpc("assistant_read_context", {
          p_topic: b.topic,
          p_owner: owner,
          p_show: b.showId || null,
        });
        return facts.error || facts.data == null
          ? { unavailable: true, message: "Could not verify selected records." }
          : facts.data;
      },
    );
    const settled = await meter.rpc("assistant_finish", {
      p_request: requestId,
      p_input: inputTokens,
      p_output: outputTokens,
      p_calls: calls,
      p_complete: true,
    });
    if (settled.error) throw new Error("meter_unavailable");
    return jsonResponse({ answer, checked, request_id: requestId });
  } catch (error) {
    if (reserved && requestId) {
      try {
        await serviceClient().rpc("assistant_finish", {
          p_request: requestId,
          p_input: inputTokens,
          p_output: outputTokens,
          p_calls: calls,
          p_complete: false,
        });
      } catch { /* keep reservation */ }
    }
    // Never log questions, database results, credentials or provider responses.
    const reason = error instanceof Error ? error.message : "";
    const auth = reason === "Authentication required.";
    return jsonResponse({
      answer: auth
        ? "Sign in to use AI help."
        : reason === "invalid_request"
        ? "Please shorten your question and try again."
        : "AI help could not finish this request. Please use the help guide or contact support.",
      unavailable: true,
    }, auth ? 401 : 200);
  }
});
