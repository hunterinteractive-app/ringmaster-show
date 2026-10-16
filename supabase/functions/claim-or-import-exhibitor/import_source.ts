export type ImportSource = "ringmaster_club" | "ringmaster_breeder";
type Row = Record<string, unknown>;
type Export = { id?: unknown; profile?: unknown };
type Owner = {
  id?: string;
  email?: string;
  email_confirmed_at?: string | null;
  deleted_at?: string | null;
  banned_until?: string | null;
};
const normalized = (value: unknown) =>
  typeof value === "string" ? value.trim().toLowerCase() : "";

/** Club remains authoritative. Breeder fallback requires the source owner's verified Auth identity. */
export async function importCandidates(
  club: Row[],
  email: string,
  loadBreeder: () => Promise<Export[]>,
  verifyOwner: (id: string) => Promise<Owner | null>,
): Promise<{ matches: Row[]; source: ImportSource }> {
  if (club.length > 0) return { matches: club, source: "ringmaster_club" };
  const rows = await loadBreeder();
  const owners = new Map<string, Owner | null>();
  const matches: Row[] = [];
  for (const row of rows) {
    if (
      !row.profile || typeof row.profile !== "object" ||
      Array.isArray(row.profile) || typeof row.id !== "string" || !row.id
    ) continue;
    const profile = row.profile as Row;
    const ownerId = profile.owner_user_id;
    if (typeof ownerId !== "string" || profile.is_active === false) continue;
    if (!owners.has(ownerId)) owners.set(ownerId, await verifyOwner(ownerId));
    const owner = owners.get(ownerId);
    if (
      !owner || owner.id !== ownerId || !owner.email_confirmed_at ||
      owner.deleted_at ||
      normalized(owner.email) !== normalized(email) || !normalized(email) ||
      (owner.banned_until && Date.parse(owner.banned_until) > Date.now())
    ) continue;
    matches.push({
      ...profile,
      id: row.id,
      email,
      account_type: profile.type ?? profile.account_type,
    });
  }
  return { matches, source: "ringmaster_breeder" };
}
