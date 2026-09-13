import { sendInvitationEmail } from "./email.ts";
import { authenticatedUser, serviceClient } from "../_shared/supabase.ts";
import { errorMessage, handleOptions, jsonResponse } from "../_shared/http.ts";

Deno.serve(async (request: Request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  try {
    const { user, client } = await authenticatedUser(request);
    const body = await request.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const { data, error } = await client.rpc("household_access", {
      p_action: "invite",
      p_email: email,
    });
    if (error) throw new Error(error.message);
    const invitation = data.invitations?.find((
      i: { email: string; is_owner: boolean },
    ) => i.email === email && i.is_owner);
    if (!invitation) throw new Error("Invitation unavailable.");
    const backend = serviceClient();
    const { data: delivery, error: preparationError } = await backend.rpc(
      "prepare_household_invitation_email",
      { p_id: invitation.id, p_owner: user.id },
    );
    if (preparationError) throw new Error(preparationError.message);
    if (delivery.send) {
      const key = Deno.env.get("RESEND_API_KEY");
      const from = Deno.env.get("RESEND_FROM_EMAIL") ??
        "RingMaster Show <noreply@ringmasterone.com>";
      if (!key) throw new Error("Invitation email is not configured yet.");
      await sendInvitationEmail({
        id: invitation.id,
        apiKey: key,
        from,
        to: delivery.to,
        inviter: delivery.inviter,
      });
      const { error: finishError } = await backend.rpc(
        "finish_household_invitation_email",
        { p_id: invitation.id, p_owner: user.id },
      );
      if (finishError) {
        throw new Error(
          "Email delivery is being confirmed. Please try again shortly.",
        );
      }
    }
    return jsonResponse({ ok: true });
  } catch (e) {
    return jsonResponse({ error: errorMessage(e) }, 400);
  }
});
