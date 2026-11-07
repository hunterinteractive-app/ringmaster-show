// Depend only on the RPC used here, so pinned SDK versions can share this helper.
type HouseholdAccessClient = {
  rpc(name: "can_access_household", params: { p_owner_user_id: string }):
    PromiseLike<{ data: unknown; error: unknown }>;
};

/** Use the caller's authenticated client, never the service client. */
export async function assertHouseholdAccess(client: HouseholdAccessClient, ownerId: string): Promise<void> {
  const {data, error} = await client.rpc("can_access_household", {p_owner_user_id: ownerId});
  if (error || data !== true) throw new Error("You do not have access to this household.");
}
