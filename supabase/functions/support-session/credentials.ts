export type SupportCredentials = {
  access_token: string;
  refresh_token?: string;
};
export function parseCredentials(value: string): SupportCredentials {
  // Existing sessions can finish normally; new sessions keep both tokens sealed.
  if (!value.startsWith("{")) return { access_token: value };
  const result = JSON.parse(value);
  if (
    typeof result.access_token !== "string" ||
    typeof result.refresh_token !== "string"
  ) {
    throw new Error("Invalid support credentials.");
  }
  return result;
}
export function tokenClaims(token: string) {
  return JSON.parse(
    atob(token.split(".")[1].replaceAll("-", "+").replaceAll("_", "/")),
  );
}
export function needsRefresh(token: string, now = Date.now() / 1000): boolean {
  return tokenClaims(token).exp <= now + 300;
}
export function checkedRefresh(
  target: string,
  result: {
    user: { id: string } | null;
    session: { access_token: string; refresh_token: string } | null;
  },
): SupportCredentials {
  if (
    result.user?.id !== target || !result.session?.access_token ||
    !result.session.refresh_token
  ) {
    throw new Error("Support session ended. Reopen Support Mode.");
  }
  return {
    access_token: result.session.access_token,
    refresh_token: result.session.refresh_token,
  };
}
