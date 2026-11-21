export interface PriorReportDelivery {
  artifact_id: string;
  recipient_email: string;
  sent_at: string | null;
  provider_message_id: string | null;
}

/** A provider-accepted send remains a send after delivery/open/bounce webhooks.
 * Subject, secretary message and regeneration do not authorize another send.
 */
export async function selectUnsentReportArtifacts<T extends { id: string }>(
  artifacts: T[],
  recipients: string[],
  forceResend: boolean,
  loadHistory: (from: number, to: number) => Promise<PriorReportDelivery[]>,
) {
  if (forceResend) {
    return { artifacts, alreadySentIds: [], priorDelivery: null };
  }

  const requested = [...new Set(recipients.map((s) => s.trim().toLowerCase()))];
  const sentTo = new Map<string, Set<string>>();
  let priorDelivery: PriorReportDelivery | null = null;
  const pageSize = 500;
  for (let from = 0;; from += pageSize) {
    // Let errors propagate: never send when delivery history cannot be checked.
    const rows = await loadHistory(from, from + pageSize - 1);
    for (const row of rows) {
      if (!row.sent_at) continue;
      const addresses = row.recipient_email.split(",").map((s) =>
        s.trim().toLowerCase()
      );
      if (!addresses.some((email) => requested.includes(email))) continue;
      priorDelivery ??= row;
      const sent = sentTo.get(row.artifact_id) ?? new Set<string>();
      addresses.forEach((email) => sent.add(email));
      sentTo.set(row.artifact_id, sent);
    }
    if (rows.length < pageSize) break;
  }
  const alreadySentIds: string[] = [];
  const pending = artifacts.filter((artifact) => {
    const sent = sentTo.get(artifact.id);
    const count = requested.filter((email) => sent?.has(email)).length;
    if (count > 0 && count < requested.length) {
      throw new Error(
        "Some recipients already received these reports. Send to the new recipients separately, or explicitly choose Resend.",
      );
    }
    if (count === requested.length) {
      alreadySentIds.push(artifact.id);
      return false;
    }
    return true;
  });
  return { artifacts: pending, alreadySentIds, priorDelivery };
}

export function reportEmailAttemptIdentity(
  showId: string,
  recipients: string[],
  artifactIds: string[],
  forceResend: boolean,
): string {
  return [
    showId,
    [...new Set(recipients.map((email) => email.trim().toLowerCase()))].sort()
      .join(","),
    [...new Set(artifactIds)].sort().join(","),
    // Normal retries/double-clicks reuse a provider key. Only an explicit
    // resend starts a new provider attempt within its 24-hour dedup window.
    forceResend ? crypto.randomUUID() : "initial-send",
  ].join("|");
}
