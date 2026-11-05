# Acting for an account in Support Mode

An authorized super admin can select a verified user in **View As User** and perform the user's RingMaster Show tasks. The support banner identifies the selected account. Show ownership, license consumption, club membership, staff records, entries, and reports use the selected user's normal data permissions. Creating a show does not give the selected account any of the operator's global privileges.

The administrator stays signed in as themselves. A web tab stores only a support-session identifier. The Show client resumes that session through the broker before loading any show data, including after a payment redirect or browser refresh. Exit returns to the real administrator. Other tabs keep their own workspace. A failed resume does not fall back to the administrator on the old screen.

## Authorization and audit

The broker verifies the administrator's Auth bearer and rechecks their login session, live super-admin role, and explicit operator grant on every request. The private database record binds that login to one target for at most 30 minutes. It records the start, end, selected user, operator, and requested application resource. Removing the operator grant or super-admin role cuts off further delegated requests. A new delegation from the same login supersedes the previous one. Super admins without an operator grant retain the existing preview.

For an approved ordinary email account, the broker uses the Supabase Admin link API and verifies the link **on the server**, without emailing it. This creates a temporary Auth login for the target and can update its last-sign-in timestamp. The target's refresh token is never stored by RingMaster. The access token is encrypted, kept in a private table, and sent only to the Show data APIs and the existing fixed Breeder connection endpoint. The support browser receives neither the login link nor a usable target token. Ending the delegation clears the stored credential and logs out only that temporary login. Expired workspaces cannot make new requests.

The broker will not start a writable session for another super admin, an unverified, banned or deleted account, SSO accounts, accounts with a verified MFA factor, or an account with a pending sign-in code. Auth endpoints, service-only functions and webhooks are not routable. Support does not sign anyone's legal agreements. Payment processor authorization and checkout still require their normal external steps.

## Release and rollback

1. Confirm the project's Auth configuration permits concurrent sessions. This implementation opens a temporary target login; **do not enable operators** on a project where a new login displaces the user's existing session.
2. Apply the audited support-session migration, then deploy the `support-session` Edge Function. Publish the matching Flutter client. The migration contains **no operator grants**.
3. Enable only the intended verified super-admin ID in `support_session_private.operators`. The table is not exposed to application clients. Use Supabase project administration for this one-time grant.
4. To disable delegated writes for an operator, remove their operator row. To disable all writes, remove all operator grants. Verification happens before every forwarded request. The unchanged preview remains available.

The static web deployment alone does not install the broker or grant access. The isolated rehearsal in `tool/support_session_e2e` checks the live Auth, REST, Edge, and Storage path without using customer accounts or payment processors.
