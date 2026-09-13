import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

/** Use the caller's authenticated client, never the service client. */
export async function assertHouseholdAccess(client: SupabaseClient, ownerId: string): Promise<void> {
  const {data, error} = await client.rpc("can_access_household", {p_owner_user_id: ownerId});
  if (error || data !== true) throw new Error("You do not have access to this household.");
}
