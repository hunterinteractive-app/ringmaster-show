import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { randomState, sha256 } from "../_shared/token_crypto.ts";
import { ApiError, createHandler } from "./handler.ts";

export function partnerHandler(
  provider: "herdmaster" | "pedigreehq" = "herdmaster",
  client = serviceClient(),
) {
  return createHandler({
    async user(request) {
      try {
        const { user } = await authenticatedUser(request);
        if (!user.email_confirmed_at) throw new Error("Unverified account");
        return user.id;
      } catch {
        throw new ApiError(
          401,
          "unauthorized",
          "A signed-in, verified RingMaster account is required.",
        );
      }
    },
    async connect(owner, externalAccount) {
      const token = `rmhm_${randomState()}`;
      const refreshToken = `rmhmr_${randomState()}`;
      const expires = new Date(Date.now() + 3600000).toISOString();
      const refreshExpires = new Date(Date.now() + 180 * 86400000)
        .toISOString();
      const { data, error } = await client.from("herdmaster_connections")
        .upsert({
          provider,
          existing_animals_consent: true,
          owner_user_id: owner,
          external_account_id: externalAccount,
          token_hash: await sha256(token),
          expires_at: expires,
          refresh_token_hash: await sha256(refreshToken),
          refresh_expires_at: refreshExpires,
          refresh_generation: crypto.randomUUID(),
          revoked_at: null,
        }, { onConflict: "provider,owner_user_id,external_account_id" }).select(
          "id",
        )
        .single();
      if (error) throw new Error("Connection unavailable");
      return {
        connection_id: data.id,
        token,
        token_type: "Bearer",
        expires_at: expires,
        refresh_token: refreshToken,
        refresh_expires_at: refreshExpires,
        scopes: [
          "animals:write",
          "animals:read",
          "results:read",
          "reports:read",
        ],
      };
    },
    async refresh(oldRefreshToken) {
      const check = await client.from("herdmaster_connections").select(
        "id,existing_animals_consent",
      ).eq("provider", provider).eq(
        "refresh_token_hash",
        await sha256(oldRefreshToken),
      ).maybeSingle();
      if (check.error || !check.data) {
        throw new ApiError(401, "unauthorized", "Invalid provider credential");
      }
      const token = `rmhm_${randomState()}`;
      const refreshToken = `rmhmr_${randomState()}`;
      const { data, error } = await client.rpc("herdmaster_rotate_refresh", {
        p_old_refresh_hash: await sha256(oldRefreshToken),
        p_new_access_hash: await sha256(token),
        p_new_refresh_hash: await sha256(refreshToken),
      });
      if (error) {
        console.error(JSON.stringify({
          event: "herdmaster_refresh_database_failure",
          code: error.code ?? null,
        }));
        throw new Error("Refresh unavailable");
      }
      if (data?.status !== "rotated") {
        throw new ApiError(
          401,
          data?.status === "reused"
            ? "refresh_token_reused"
            : "invalid_refresh_token",
          "The refresh token is invalid, expired, revoked, or already used. Please reconnect your account.",
        );
      }
      return {
        connection_id: data.connection_id,
        token,
        token_type: "Bearer",
        expires_at: data.expires_at,
        refresh_token: refreshToken,
        refresh_expires_at: data.refresh_expires_at,
        scopes: [
          "animals:write",
          ...(check.data.existing_animals_consent ? ["animals:read"] : []),
          "results:read",
          "reports:read",
        ],
      };
    },
    async revoke(owner, id) {
      const { data, error } = await client.from("herdmaster_connections")
        .update({
          revoked_at: new Date().toISOString(),
          refresh_token_hash: null,
          refresh_expires_at: null,
        }).eq("provider", provider).eq("id", id).eq(
          "owner_user_id",
          owner,
        ).select("id");
      if (error) throw new Error("Revocation unavailable");
      return data.length > 0;
    },
    async rpc(name, args) {
      if (args.p_hash) {
        const check = await client.from("herdmaster_connections").select("id")
          .eq("provider", provider).eq("token_hash", args.p_hash).maybeSingle();
        if (check.error || !check.data) {
          throw new ApiError(
            401,
            "unauthorized",
            "Invalid provider credential",
          );
        }
      }
      const { data, error } = await client.rpc(name, args);
      if (error) {
        console.error(
          JSON.stringify({
            event: "herdmaster_rpc_failed",
            rpc: name,
            code: error.code,
          }),
        );
        if (error.code === "42501") {
          throw new ApiError(
            403,
            "consent_required",
            "Reconnect with permission to review existing Show animals.",
          );
        }
        if (error.code === "28000") {
          throw new ApiError(
            401,
            "unauthorized",
            "Connection token is invalid, expired, or revoked.",
          );
        }
        if (error.code === "23505") {
          throw new ApiError(
            409,
            "version_conflict",
            "The same animal version has different data. Send a newer updated_at.",
          );
        }
        if (["22023", "22007", "22008", "22P02"].includes(error.code)) {
          throw new ApiError(
            422,
            "invalid_animal_data",
            "Animal data is invalid or an existing animal cannot be linked. Check the field mapping.",
          );
        }
        throw new Error("Database unavailable");
      }
      return data;
    },
    hash: sha256,
    async sign(bucket, path) {
      const { data, error } = await client.storage.from(bucket).createSignedUrl(
        path,
        300,
      );
      if (error) throw new Error("Report unavailable");
      return data.signedUrl;
    },
  });
}
