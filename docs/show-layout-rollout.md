# Show layout rollout

The rollout applies to Show Secretary and Exhibitor together. Choose the phase with the GitHub Actions repository variable `SHOW_LAYOUT_ROLLOUT`, then run **Deploy Flutter Web to Cloudflare Pages** for the intended branch. The workflow uses Super Admin preview if the variable is unset.

| Value | Default layout | Account Settings switch |
| --- | --- | --- |
| `super_admin_preview` | Classic | Signed-in Super Admins |
| `opt_in` | Classic | Signed-in users |
| `launched` | Updated | Hidden |
| `classic` | Classic | Hidden |

In the two preview phases, go to **Account Settings → Use updated layout**. The choice persists for the signed-in account on that browser or device. Super Admin preview checks the signed-in actor against the existing Super Admin role records. Support impersonation and the shared demo omit the preference.

To test a phase locally, pass it to Flutter. For example, `flutter run -d chrome --dart-define=SHOW_LAYOUT_ROLLOUT=opt_in`.
