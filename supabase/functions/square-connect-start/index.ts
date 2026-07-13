import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";
import {
  assertCanManageShowSettings,
  assertShowUnlocked,
  authenticatedUser,
  serviceClient,
} from "../_shared/supabase.ts";
import {
  squareConnectBase,
  squareEnv,
  squareScopes,
} from "../_shared/square.ts";
import { randomState, sha256 } from "../_shared/token_crypto.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const body = await request.json() as { show_id?: string };
    const showId = body.show_id?.trim() ?? "";
    if (!showId) return jsonResponse({ error: "show_id is required." }, 400);

    const { user, client } = await authenticatedUser(request);
    await assertCanManageShowSettings(client, showId, user.id);
    const admin = serviceClient();
    await assertShowUnlocked(admin, showId);

    const state = randomState();
    const { error } = await admin.from("payment_provider_oauth_states").insert({
      state_hash: await sha256(state),
      provider: "square",
      show_id: showId,
      user_id: user.id,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    });
    if (error) throw new Error("Unable to start the Square connection.");

    const authorizationUrl = new URL(`${squareConnectBase}/oauth2/authorize`);
    authorizationUrl.searchParams.set(
      "client_id",
      squareEnv("SQUARE_APPLICATION_ID"),
    );
    authorizationUrl.searchParams.set("scope", squareScopes.join(" "));
    authorizationUrl.searchParams.set("state", state);
    authorizationUrl.searchParams.set("session", "false");
    authorizationUrl.searchParams.set(
      "redirect_uri",
      squareEnv("SQUARE_REDIRECT_URI"),
    );

    return jsonResponse({ authorization_url: authorizationUrl.toString() });
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }
});
