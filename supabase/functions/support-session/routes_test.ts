import { proxyTargetPath, route } from "./routes.ts";
Deno.test("scope support requests to intended application resources", () => {
  for (
    const [path, valid] of [
      ["/rest/v1/shows", true],
      ["/rest/v1/rpc/create_show_with_license", true],
      ["/functions/v1/refund-show-entries", true],
      ["/storage/v1/object/show-files/report.pdf", true],
      ["/auth/v1/user", false],
      ["/functions/v1/support-session", false],
      ["//evil.org/rest/v1/shows", false],
      ["/rest/v1/rpc/manage_support_session", false],
      ["/rest/v1/shows/%252e%252e", false],
      ["/storage/v1/object/%2e%2e/auth", false],
      ["/functions/v1/stripe-webhook", false],
    ] as const
  ) if (!!route(path) !== valid) throw new Error(path);
});

Deno.test("gateway-safe aliases retain the same function permissions", () => {
  for (
    const [path, expected] of [
      ["/invoke/payment-quote-preview", "function/payment-quote-preview"],
      ["/invoke/animal-sync", "function/animal-sync"],
      ["/invoke/support-session", null],
      ["/invoke/stripe-webhook", null],
      ["/invoke/../auth/v1/user", null],
      ["/invoke/%2e%2e/auth/v1/user", null],
      ["/functions/v1/payment-quote-preview", "function/payment-quote-preview"],
    ] as const
  ) {
    if (route(proxyTargetPath(path)) !== expected) throw new Error(path);
  }
});
