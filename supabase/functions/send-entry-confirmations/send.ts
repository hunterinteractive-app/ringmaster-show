export async function sendConfirmation(
  apiKey: string,
  cartId: string,
  payload: unknown,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const response = await fetcher("https://api.resend.com/emails", {
    method: "POST",
    signal: AbortSignal.timeout(10000),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": `entry-confirmation/${cartId}`,
    },
    body: JSON.stringify(payload),
  });
  const result = await response.json();
  if (!response.ok || typeof result.id !== "string" || !result.id) {
    throw new Error(`Email provider rejected send (${response.status})`);
  }
  return result.id;
}
