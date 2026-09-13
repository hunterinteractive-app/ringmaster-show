export async function sendInvitationEmail(args: {
  id: string;
  apiKey: string;
  from: string;
  to: string;
  inviter: string;
  fetcher?: typeof fetch;
}): Promise<void> {
  const response = await (args.fetcher ?? fetch)(
    "https://api.resend.com/emails",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `household-invitation-${args.id}`,
      },
      body: JSON.stringify({
        from: args.from,
        to: [args.to],
        subject: "You’re invited to a RingMaster Show household",
        text:
          `${args.inviter} invited you to share their RingMaster Show household.\n\nSign in at https://show.ringmasterone.com using ${args.to}, then open Account Settings → Household Access and accept the invitation within 7 days. Use your own login code; you do not need anyone else's code.\n\nYou will have access to the household’s exhibitors, animals, entries, and exhibitor reports. Show Secretary and admin permissions are separate and are not shared. Your existing personal household stays separate.\n\nIf you were not expecting this invitation, you can ignore it.`,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(
      "The invitation was created, but its email could not be sent. Please try again.",
    );
  }
}
