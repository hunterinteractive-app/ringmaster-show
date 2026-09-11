export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error && typeof error === 'object') {
    const e = error as Record<string, unknown>;
    return [e.code, e.message, e.details, e.hint].filter(Boolean).join(': ') || JSON.stringify(e);
  }
  return String(error);
}
// Keep fetching until an empty page: the API may cap rows below our request.
export async function loadAllPages<T>(fetchPage: (from: number, to: number) => Promise<T[]>): Promise<T[]> {
  const rows: T[] = [];
  for (;;) {
    const page = await fetchPage(rows.length, rows.length + 499);
    if (!page.length) return rows;
    rows.push(...page);
  }
}
export function retryWindowOpen(firstAttempt: string, now = Date.now()): boolean {
  return now - Date.parse(firstAttempt) < 23 * 60 * 60 * 1000;
}
