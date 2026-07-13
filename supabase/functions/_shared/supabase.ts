import {
  createClient,
  SupabaseClient,
  User,
} from "npm:@supabase/supabase-js@2";

function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing server configuration: ${name}.`);
  return value;
}

export function serviceClient(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export async function authenticatedUser(
  request: Request,
): Promise<{ user: User; client: SupabaseClient }> {
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new Error("Authentication required.");
  }

  const client = createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_ANON_KEY"),
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new Error("Authentication required.");
  return { user: data.user, client };
}

export async function assertCanManageShowSettings(
  client: SupabaseClient,
  showId: string,
  userId: string,
): Promise<void> {
  let result = await client.rpc("user_can_manage_show_settings", {
    p_show_id: showId,
    p_user_id: userId,
  });

  if (result.error?.code === "PGRST202") {
    result = await client.rpc("user_can_manage_show_settings", {
      p_show_id: showId,
    });
  }

  if (result.error) throw new Error("Unable to verify show permissions.");
  if (result.data !== true) {
    throw new Error(
      "You do not have permission to manage this show's payments.",
    );
  }
}

export async function assertShowUnlocked(
  client: SupabaseClient,
  showId: string,
): Promise<void> {
  const { data, error } = await client
    .from("shows")
    .select("is_locked,finalized_at")
    .eq("id", showId)
    .single();
  if (error || !data) throw new Error("Show not found.");
  if (data.is_locked === true) {
    throw new Error(
      "This show is locked. Unlock it before changing payment settings.",
    );
  }
  if (data.finalized_at) {
    throw new Error("This show is finalized. Payment settings are read-only.");
  }
}
