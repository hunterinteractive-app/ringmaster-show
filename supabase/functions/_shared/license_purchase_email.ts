export type LicensePurchaseEmailType = "welcome" | "returning";

export type LicensePurchaseEmail = {
  subject: string;
  html: string;
};

export function isCompletedLicenseCheckoutEvent(eventType: unknown): boolean {
  return eventType === "checkout.session.completed";
}

export function isCompletedSuccessfulLicensePurchase(
  sessionStatus: unknown,
  paymentStatus: unknown,
): boolean {
  return sessionStatus === "complete" && paymentStatus === "paid";
}

export function normalizeSecretaryEmail(value: unknown): string | null {
  const email = String(value ?? "").trim().toLowerCase();
  if (!email || email.length > 320 || /\s/.test(email)) return null;
  if (!/^[^@]+@[^@]+\.[^@]+$/.test(email)) return null;
  return email;
}

export function licensePurchaseEmail(
  type: LicensePurchaseEmailType,
  secretaryName?: string | null,
): LicensePurchaseEmail {
  const name = String(secretaryName ?? "").trim();
  const greeting = name ? `Hello ${escapeHtml(name)},` : "Hello,";

  if (type === "welcome") {
    return {
      subject: "Welcome to RingMaster Show — Let’s Get Started!",
      html: `
        <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #1f2937;">
          <p>${greeting}</p>
          <p>Welcome to RingMaster Show! Your token purchase is complete and your account is ready to get started.</p>
          <p><a href="https://show.ringmasterone.com">Log in to RingMaster Show</a> using the show secretary email address provided during purchase.</p>
          <p>Your first guide is available at <a href="https://www.ringmasterone.com/help_secretaries.html">RingMaster Show Help for Secretaries</a>.</p>
          <p>You can find additional guides in the app under <strong>Show Secretary → More → Resources → RingMaster Show Help Guides</strong>.</p>
          <p>If you need help, contact <a href="mailto:support@ringmasterone.com">support@ringmasterone.com</a>.</p>
          <p>Thank you,<br>RingMaster Show</p>
        </div>
      `,
    };
  }

  return {
    subject: "Your New RingMaster Show Token Is Ready",
    html: `
      <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #1f2937;">
        <p>${greeting}</p>
        <p>Thank you for purchasing another RingMaster Show token. Your new token is now available.</p>
        <p><a href="https://show.ringmasterone.com">Log in to RingMaster Show</a> to continue managing your shows.</p>
        <p>Help guides are available in the app under <strong>Show Secretary → More → Resources → RingMaster Show Help Guides</strong>.</p>
        <p>If you need help, contact <a href="mailto:support@ringmasterone.com">support@ringmasterone.com</a>.</p>
        <p>Thank you,<br>RingMaster Show</p>
      </div>
    `,
  };
}

export async function sendLicensePurchaseEmail(args: {
  apiKey: string;
  from: string;
  to: string;
  type: LicensePurchaseEmailType;
  secretaryName?: string | null;
  fetcher?: typeof fetch;
}): Promise<string | null> {
  const content = licensePurchaseEmail(args.type, args.secretaryName);
  const response = await (args.fetcher ?? fetch)(
    "https://api.resend.com/emails",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: args.from,
        to: [args.to],
        subject: content.subject,
        html: content.html,
      }),
    },
  );

  const payload = await response.json().catch(() => ({})) as Record<
    string,
    unknown
  >;
  if (!response.ok) {
    throw new Error(
      `Resend license purchase email failed (${response.status}): ${
        JSON.stringify(payload).slice(0, 700)
      }`,
    );
  }
  return typeof payload.id === "string" ? payload.id : null;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
