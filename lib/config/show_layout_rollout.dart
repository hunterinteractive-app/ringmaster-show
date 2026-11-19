enum ShowLayoutRollout {
  classic,
  superAdminPreview,
  optIn,
  launched;

  static const buildValue = String.fromEnvironment(
    'SHOW_LAYOUT_ROLLOUT',
    defaultValue: 'super_admin_preview',
  );

  static ShowLayoutRollout get current => fromValue(buildValue);

  static ShowLayoutRollout fromValue(String value) => switch (value) {
    'super_admin_preview' => superAdminPreview,
    'opt_in' => optIn,
    'launched' => launched,
    _ => classic,
  };

  bool canChoose({required bool isSuperAdmin}) =>
      this == optIn || (this == superAdminPreview && isSuperAdmin);

  bool usesUpdated({required bool isSuperAdmin, required bool optedIn}) =>
      this == launched || (optedIn && canChoose(isSuperAdmin: isSuperAdmin));
}
