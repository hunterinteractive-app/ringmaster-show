export function ownerMail(body: Record<string, unknown>, verifiedFrom: string) {
  const email = (value: unknown) =>
    typeof value === "string" && value.length <= 254 &&
    /^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$/.test(value);
  const fromAddress = verifiedFrom.match(/<([^<>]+)>/)?.[1] ??
    verifiedFrom.trim();
  if (
    !email(fromAddress) || !email(body.owner_email) || !email(body.recipient)
  ) throw new Error("Invalid mail address");
  const name =
    String(body.owner_name ?? "Breeder").replace(/[\r\n<>"\\]/g, "").trim()
      .slice(0, 100) || "Breeder";
  const exported = body.export_json as Record<string, unknown>;
  if (
    !exported || exported.format !== "ringmaster-pedigree" ||
    exported.version !== 1 || !exported.pedigree ||
    typeof exported.pedigree !== "object"
  ) throw new Error("Invalid pedigree export");
  const animal =
    (exported.pedigree as Record<string, Record<string, unknown>>).animal;
  const animalName = String(animal?.name || animal?.tattoo || "your animal")
    .replace(/[\r\n]/g, " ").slice(0, 100);
  const json = JSON.stringify(exported, null, 2);
  if (json.length > 200000) throw new Error("Pedigree is too large");
  if (
    typeof body.pdf !== "string" || body.pdf.length > 5600000 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(body.pdf) ||
    !atob(body.pdf).startsWith("%PDF-")
  ) throw new Error("Invalid PDF");
  const bytes = new TextEncoder().encode(json);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return {
    from: `"${name}" <${fromAddress}>`,
    to: [body.recipient],
    reply_to: body.owner_email,
    subject: `Pedigree for ${animalName}`,
    text:
      `Hello,\n\nAttached is the pedigree for ${animalName}, as a PDF and a JSON file.\n\nThank you,\n${name}\n${body.owner_email}`,
    attachments: [{
      filename: "pedigree.pdf",
      content: body.pdf,
      content_type: "application/pdf",
    }, {
      filename: "pedigree.json",
      content: btoa(binary),
      content_type: "application/json",
    }],
  };
}
export async function sendOwnerMail(
  payload: ReturnType<typeof ownerMail>,
  requestId: string,
  key: string,
  fetcher: typeof fetch = fetch,
) {
  const response = await fetcher("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `breeder-pedigree/${requestId}`,
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(20000),
  });
  if (!response.ok) {
    throw new Error("Email provider did not confirm acceptance");
  }
  const data = await response.json();
  if (typeof data.id !== "string") {
    throw new Error("Email confirmation unavailable");
  }
  return data.id as string;
}

export async function relayAuthorized(header: string, expected: string) {
  if (!expected || !header.startsWith("Bearer ")) return false;
  const provided = header.slice(7);
  const hash = async (v: string) =>
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(v)),
    );
  const [a, b] = await Promise.all([hash(provided), hash(expected)]);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}
