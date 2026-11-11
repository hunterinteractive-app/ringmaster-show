type LicenseUser = { id: string; email?: string };

type LicenseUserDirectory = {
  listUsers(params: { page: number; perPage: number }): Promise<{
    data: { users: LicenseUser[] };
    error: unknown;
  }>;
};

// listUsers() only returns one page; an existing secretary can be on any page.
export async function findLicenseUserByEmail(
  directory: LicenseUserDirectory,
  email: string,
): Promise<LicenseUser | null> {
  const normalizedEmail = email.trim().toLowerCase();
  const perPage = 1000;

  for (let page = 1;; page++) {
    const { data, error } = await directory.listUsers({ page, perPage });
    // A failed lookup must retry the webhook, never queue an existing account.
    if (error) throw error;

    const user = data.users.find((user) =>
      user.email?.trim().toLowerCase() === normalizedEmail
    );
    if (user) return user;
    if (data.users.length < perPage) return null;
  }
}
