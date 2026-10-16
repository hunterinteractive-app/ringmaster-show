import { partnerHandler } from "../herdmaster-api/partner.ts";
const handler = partnerHandler("pedigreehq");
Deno.serve(async (request: Request) => {
  const url = new URL(request.url);
  url.pathname = url.pathname.replace("/pedigreehq-api", "/herdmaster-api");
  let body: string | undefined;
  if (request.method !== "GET" && request.method !== "OPTIONS") {
    const reader = request.body?.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    if (reader) {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        total += part.value.length;
        if (total > 1048576) {
          await reader.cancel();
          return new Response("Request too large", { status: 413 });
        }
        chunks.push(part.value);
      }
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const part of chunks) {
      bytes.set(part, offset);
      offset += part.length;
    }
    const raw = new TextDecoder().decode(bytes);
    try {
      const data = JSON.parse(raw);
      if (data.pedigreehq_account_id !== undefined) {
        data.herdmaster_account_id = data.pedigreehq_account_id;
        delete data.pedigreehq_account_id;
      }
      body = JSON.stringify(data);
    } catch {
      body = raw;
    }
  }
  const response = await handler(
    new Request(url, {
      method: request.method,
      headers: request.headers,
      body,
    }),
  );
  const raw = await response.text();
  let text = raw;
  try {
    const data = JSON.parse(raw);
    if (Array.isArray(data.data)) {
      data.data = data.data.map((row: Record<string, unknown>) => {
        if (!Object.hasOwn(row, "herdmaster_animal_id")) return row;
        const { herdmaster_animal_id, ...rest } = row;
        return { ...rest, pedigreehq_animal_id: herdmaster_animal_id };
      });
    }
    if (data.error?.message) {
      data.error.message = data.error.message.replaceAll(
        "HerdMaster",
        "Pedigree HQ",
      );
    }
    text = JSON.stringify(data);
  } catch { /* OPTIONS and plain gateway errors have no JSON payload. */ }
  return new Response(text, {
    status: response.status,
    headers: response.headers,
  });
});
