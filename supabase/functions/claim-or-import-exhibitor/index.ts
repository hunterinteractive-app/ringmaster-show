import { budgetedFetch, authErrorStatus, UpstreamUnavailable } from "../_shared/request_fetch.ts";
// supabase/functions/claim-or-import-exhibitor/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.110.2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type RequestBody = {
  action?: "lookup" | "claim";
  exhibitor_id?: string;
};

type ShowExhibitorMatch = {
  id: string;
  display_name: string | null;
  showing_name: string | null;
  first_name: string | null;
  last_name: string | null;
  email: string | null;
  phone: string | null;
  city: string | null;
  state: string | null;
  created_at: string | null;
  updated_at: string | null;
};

type ClubExhibitor = {
  id: string;
  account_type: string | null;
  display_name: string | null;
  first_name: string | null;
  last_name: string | null;
  showing_name: string | null;
  email: string | null;
  phone: string | null;
  address_line1: string | null;
  address_line2: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  birth_date: string | null;
  arba_number: string | null;
  source_exhibitor_number: string | number | null;
  is_public_entry: boolean | null;
  print_phone_on_reports: boolean | null;
  group_members: unknown;
  is_active: boolean | null;
  updated_at: string | null;
};

type SavedExhibitor = {
  id: string;
  display_name: string | null;
  showing_name: string | null;
};

function json(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function clean(value: unknown): string | null {
  const text = (value ?? "").toString().trim();
  return text.length === 0 ? null : text;
}

function normalizeEmail(value: unknown): string | null {
  return clean(value)?.toLowerCase() ?? null;
}

function buildName(values: {
  displayName?: unknown;
  showingName?: unknown;
  firstName?: unknown;
  lastName?: unknown;
}): string | null {
  const generated = [
    clean(values.firstName),
    clean(values.lastName),
  ]
    .filter((value): value is string => value != null)
    .join(" ")
    .trim();

  return (
    clean(values.displayName) ??
    clean(values.showingName) ??
    clean(generated)
  );
}

function maskPhone(value: unknown): string | null {
  const digits = clean(value)?.replace(/\D/g, "") ?? "";

  if (digits.length < 4) {
    return null;
  }

  return digits.slice(-4);
}

function isUuid(value: unknown): value is string {
  if (typeof value !== "string") return false;

  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value.trim());
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return json(
      {
        status: "error",
        message: "Method not allowed.",
      },
      405,
    );
  }

  const showUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const showAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const showServiceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const clubUrl =
    Deno.env.get("CLUB_SUPABASE_URL") ?? "";

  const clubServiceRoleKey =
    Deno.env.get("CLUB_SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (
    !showUrl ||
    !showAnonKey ||
    !showServiceRoleKey ||
    !clubUrl ||
    !clubServiceRoleKey
  ) {
    return json(
      {
        status: "error",
        message:
          "Required Supabase environment variables are missing.",
      },
      500,
    );
  }

  const authorization = req.headers.get("Authorization");

  if (!authorization) {
    return json(
      {
        status: "unauthorized",
        message: "An authorization header is required.",
      },
      401,
    );
  }

  let body: RequestBody = {};

  try {
    const parsed = await req.json();

    if (
      parsed != null &&
      typeof parsed === "object" &&
      !Array.isArray(parsed)
    ) {
      body = parsed as RequestBody;
    }
  } catch {
    // An empty request body is valid and means "perform lookup".
  }

  const action = body.action ?? "lookup";

  if (action !== "lookup" && action !== "claim") {
    return json(
      {
        status: "error",
        message: "Unsupported action.",
      },
      400,
    );
  }

  // Share one deadline across Auth, Show and Club so upstream stalls cannot
  // keep registration waiting for a minute or more.
  const upstreamDeadline = AbortSignal.timeout(12_000);
  try {
    /*
     * Authenticate against the RingMaster Show project.
     * This client uses only the caller's JWT.
     */
    const showUserClient = createClient(
      showUrl,
      showAnonKey,
      {
        global: {
          fetch: budgetedFetch("account_auth", upstreamDeadline),
          headers: {
            Authorization: authorization,
          },
        },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const {
      data: { user },
      error: userError,
    } = await showUserClient.auth.getUser();

    if (upstreamDeadline.aborted) throw new UpstreamUnavailable();
    if (userError || !user) {
      return json(
        {
          status: "unauthorized",
          message:
            userError?.message ??
            "No authenticated RingMaster Show user was found.",
        },
        authErrorStatus(userError),
      );
    }

    const verifiedEmail = normalizeEmail(user.email);

    if (!verifiedEmail || !user.email_confirmed_at) {
      return json(
        {
          status: "missing_email",
          message:
            "The authenticated account must have a verified email address.",
        },
        400,
      );
    }

    const showAdmin = createClient(
      showUrl,
      showServiceRoleKey,
      {
        global: { fetch: budgetedFetch("account_show", upstreamDeadline) },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    const clubAdmin = createClient(
      clubUrl,
      clubServiceRoleKey,
      {
        global: { fetch: budgetedFetch("account_club", upstreamDeadline) },
        auth: {
          persistSession: false,
          autoRefreshToken: false,
        },
      },
    );

    /*
     * First check whether this Show user already owns an active
     * exhibitor record.
     */
    const {
      data: existingOwned,
      error: existingOwnedError,
    } = await showAdmin
      .from("exhibitors")
      .select("id, display_name, showing_name")
      .eq("owner_user_id", user.id)
      .eq("is_active", true)
      .limit(1)
      .maybeSingle();

    if (existingOwnedError) {
      throw existingOwnedError;
    }

    if (existingOwned) {
      const displayName = buildName({
        displayName: existingOwned.display_name,
        showingName: existingOwned.showing_name,
      });

      return json({
        status: "already_exists",
        exhibitor_id: existingOwned.id,
        display_name: displayName,
      });
    }

    /*
     * CLAIM ACTION
     *
     * The requested record must:
     * - be included in the exact normalized-email lookup;
     * - still have no owner;
     * - still be active.
     */
    if (action === "claim") {
      if (!isUuid(body.exhibitor_id)) {
        return json(
          {
            status: "invalid_claim",
            message:
              "A valid exhibitor record ID is required.",
          },
          400,
        );
      }

      const {
        data: matchingClaimRows,
        error: matchingClaimError,
      } = await showAdmin.rpc(
        "find_unclaimed_exhibitors_by_email",
        {
          p_email: verifiedEmail,
        },
      );

      if (matchingClaimError) {
        throw matchingClaimError;
      }

      const claimMatches =
        (matchingClaimRows ?? []) as ShowExhibitorMatch[];

      const selectedMatch = claimMatches.find(
        (row) => row.id === body.exhibitor_id,
      );

      if (!selectedMatch) {
        return json(
          {
            status: "claim_not_allowed",
            message:
              "That exhibitor record is not available to this account.",
          },
          403,
        );
      }

      const now = new Date().toISOString();

      const {
        data: claimed,
        error: claimError,
      } = await showAdmin
        .from("exhibitors")
        .update({
          owner_user_id: user.id,
          claimed_at: now,
          claimed_by_user_id: user.id,
          updated_at: now,
        })
        .eq("id", selectedMatch.id)
        .is("owner_user_id", null)
        .eq("is_active", true)
        .select("id, display_name, showing_name")
        .maybeSingle();

      if (claimError) {
        throw claimError;
      }

      if (!claimed) {
        return json(
          {
            status: "claim_unavailable",
            message:
              "That exhibitor record has already been claimed.",
          },
          409,
        );
      }

      const displayName = buildName({
        displayName: claimed.display_name,
        showingName: claimed.showing_name,
        firstName: selectedMatch.first_name,
        lastName: selectedMatch.last_name,
      });

      const {
        error: profileError,
      } = await showAdmin
        .from("profiles")
        .upsert(
          {
            user_id: user.id,
            email: verifiedEmail,
            display_name: displayName,
            updated_at: now,
          },
          {
            onConflict: "user_id",
          },
        );

      if (profileError) {
        throw profileError;
      }

      return json({
        status: "claimed",
        exhibitor_id: claimed.id,
        display_name: displayName,
      });
    }

    /*
     * LOOKUP ACTION
     *
     * Secretary-created Show accounts take priority over importing
     * a new record from RingMaster Club.
     */
    const {
      data: unclaimedRows,
      error: unclaimedError,
    } = await showAdmin.rpc(
      "find_unclaimed_exhibitors_by_email",
      {
        p_email: verifiedEmail,
      },
    );

    if (unclaimedError) {
      throw unclaimedError;
    }

    const unclaimed =
      (unclaimedRows ?? []) as ShowExhibitorMatch[];

    if (unclaimed.length === 1) {
      const match = unclaimed[0];

      return json({
        status: "claim_confirmation_required",
        match: {
          id: match.id,
          display_name: buildName({
            displayName: match.display_name,
            showingName: match.showing_name,
            firstName: match.first_name,
            lastName: match.last_name,
          }),
          city: clean(match.city),
          state: clean(match.state)?.toUpperCase() ?? null,
          phone_last_four: maskPhone(match.phone),
        },
      });
    }

    if (unclaimed.length > 1) {
      return json({
        status: "multiple_unclaimed_matches",
        matches: unclaimed.map((match) => ({
          id: match.id,
          display_name: buildName({
            displayName: match.display_name,
            showingName: match.showing_name,
            firstName: match.first_name,
            lastName: match.last_name,
          }),
          city: clean(match.city),
          state:
            clean(match.state)?.toUpperCase() ?? null,
          phone_last_four: maskPhone(match.phone),
        })),
      });
    }

    /*
     * No unclaimed Show account exists.
     * Search RingMaster Club using an exact normalized email RPC.
     */
    const {
      data: clubRows,
      error: clubError,
    } = await clubAdmin.rpc(
      "find_exhibitors_for_show_import",
      {
        p_email: verifiedEmail,
      },
    );

    if (clubError) {
      throw clubError;
    }

    const clubMatches =
      (clubRows ?? []) as ClubExhibitor[];

    if (clubMatches.length === 0) {
      return json({
        status: "club_not_found",
      });
    }

    if (clubMatches.length > 1) {
      return json({
        status: "club_multiple_matches",
        match_count: clubMatches.length,
      });
    }

    const source = clubMatches[0];
    const now = new Date().toISOString();

    const firstName = clean(source.first_name);
    const lastName = clean(source.last_name);

    const generatedName = [
      firstName,
      lastName,
    ]
      .filter((value): value is string => value != null)
      .join(" ")
      .trim();

    const showingName =
      clean(source.showing_name) ??
      clean(source.display_name) ??
      clean(generatedName);

    const displayName =
      clean(source.display_name) ??
      clean(source.showing_name) ??
      clean(generatedName);

    const requiredValues = {
      first_name: firstName,
      last_name: lastName,
      showing_name: showingName,
      display_name: displayName,
      email:
        normalizeEmail(source.email) ??
        verifiedEmail,
      phone: clean(source.phone),
      address_line1: clean(source.address_line1),
      city: clean(source.city),
      state:
        clean(source.state)?.toUpperCase() ?? null,
      zip: clean(source.zip),
    };

    const missingFields = Object.entries(requiredValues)
      .filter(([, value]) => value == null)
      .map(([key]) => key);

    if (missingFields.length > 0) {
      return json({
        status: "incomplete_club_match",
        missing_fields: missingFields,
      });
    }

    if (requiredValues.state!.length !== 2) {
      return json({
        status: "incomplete_club_match",
        missing_fields: ["state"],
        message:
          "The Club account must use a two-letter state abbreviation.",
      });
    }

    const importValues = {
      owner_user_id: user.id,

      type: clean(source.account_type),
      display_name: requiredValues.display_name!,
      first_name: requiredValues.first_name!,
      last_name: requiredValues.last_name!,
      showing_name: requiredValues.showing_name!,

      /*
       * Always use the verified Show authentication email as the
       * imported account email.
       */
      email: verifiedEmail,
      phone: requiredValues.phone!,

      address_line1: requiredValues.address_line1!,
      address_line2: clean(source.address_line2),
      city: requiredValues.city!,
      state: requiredValues.state!,
      zip: requiredValues.zip!,

      birth_date: clean(source.birth_date),
      arba_number: clean(source.arba_number),

      is_public_entry:
        source.is_public_entry ?? false,

      print_phone_on_reports:
        source.print_phone_on_reports ?? false,

      group_members:
        source.group_members ?? null,

      is_active: true,
      is_test: false,
      is_merged: false,

      imported_from: "ringmaster_club",
      imported_source_id: source.id,
      imported_at: now,

      created_at: now,
      updated_at: now,
    };

    let imported: SavedExhibitor | null = null;
    let duplicateImport = false;

    const {
      data: inserted,
      error: insertError,
    } = await showAdmin
      .from("exhibitors")
      .insert(importValues)
      .select("id, display_name, showing_name")
      .single();

    if (insertError) {
      /*
       * PostgreSQL unique violation. This can happen when two calls
       * attempt the same import at nearly the same time.
       */
      if (insertError.code === "23505") {
        duplicateImport = true;

        const {
          data: racedExisting,
          error: racedExistingError,
        } = await showAdmin
          .from("exhibitors")
          .select("id, display_name, showing_name")
          .eq("owner_user_id", user.id)
          .eq("is_active", true)
          .limit(1)
          .maybeSingle();

        if (racedExistingError) {
          throw racedExistingError;
        }

        if (!racedExisting) {
          throw insertError;
        }

        imported = racedExisting as SavedExhibitor;
      } else {
        throw insertError;
      }
    } else {
      imported = inserted as SavedExhibitor;
    }

    if (!imported) {
      throw new Error(
        "The imported exhibitor record could not be loaded.",
      );
    }

    const finalDisplayName = buildName({
      displayName: imported.display_name,
      showingName: imported.showing_name,
      firstName: requiredValues.first_name,
      lastName: requiredValues.last_name,
    });

    const {
      error: profileError,
    } = await showAdmin
      .from("profiles")
      .upsert(
        {
          user_id: user.id,
          email: verifiedEmail,
          display_name: finalDisplayName,
          updated_at: now,
        },
        {
          onConflict: "user_id",
        },
      );

    if (profileError) {
      throw profileError;
    }

    return json({
      status:
        duplicateImport
          ? "already_exists"
          : "imported",
      exhibitor_id: imported.id,
      display_name: finalDisplayName,
    });
  } catch (error) {
    if (upstreamDeadline.aborted || error instanceof UpstreamUnavailable) {
      return json({
        status: "temporarily_unavailable",
        message: new UpstreamUnavailable().message,
      }, 503);
    }
    console.error(
      "claim-or-import-exhibitor failed",
      error,
    );

    return json(
      {
        status: "error",
        message:
          error instanceof Error
            ? error.message
            : String(error),
      },
      500,
    );
  }
});
