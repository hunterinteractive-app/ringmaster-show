# RingMaster Show project memory

## UI contrast — required for every new or changed feature

The user has repeatedly encountered unreadable text caused by inherited colors.
Treat foreground and background as a pair, including nested dialogs.

- Light cards/forms: use `AppTheme.surfaceTextScope` (or `surfaceTheme`) with
  `AppColors.surface`, dark `AppColors.text`/`muted`, and purple secondary actions.
- Purple backgrounds: use `AppTheme.gradientTextScope`/`onGradientTheme` and light
  text. Never put dark helper text or purple text buttons directly on purple.
- New form `AlertDialog`s: scope the entire dialog with
  `Theme(data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)), child: ...)`
  in the `showDialog` builder. This pairs a light dialog background with readable
  title, body, floating labels, helper/error text, switches, icons, and buttons.
  Styling the title alone or changing only `DefaultTextStyle` is insufficient.
- Keep light input text dark even when the surrounding page is purple. Check
  focused/floating labels and text outside the input fill, not just field values.
- A surface text scope does not paint a light background. Controls between
  filled inputs still sit on purple: give those rows their own gradient scope,
  including checkbox outlines, selected fill/checkmark, and disabled states.
  Test the actual newly added control inside its production parent scope;
  testing a different dialog from the same feature does not cover the form.
- Exercise the actual parent theme and nested-dialog route in regression tests;
  a plain `ThemeData.light()` harness can miss the production inheritance bug.
  Verify normal-text contrast is at least 4.5:1 and inspect the rendered dialog at
  phone width, including validation messages and secondary actions.
- Reuse the shared palette/scopes instead of one-off colors. Avoid changing the
  global dialog theme to fix a single screen; existing branded dialogs may rely
  on it. Run the color-contrast suite and relevant widget/browser tests.

Reference: `lib/theme/app_theme.dart`,
`test/accessibility_color_contrast_test.dart`, `test/entry_discount_codes_test.dart`.
