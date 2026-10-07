/// Resolve report recipients by exhibitor ID, never by display name.
/// A current contact takes priority over stale generated-report metadata.
String? exhibitorReportRecipient(
  Map<String, dynamic> metadata,
  Map<String, Map<String, dynamic>> exhibitors,
) {
  final id = (metadata['exhibitor_id'] ?? '').toString().trim();
  for (final value in [
    exhibitors[id]?['email'],
    metadata['exhibitor_email'],
    metadata['email'],
  ]) {
    final email = (value ?? '').toString().trim();
    if (email.isNotEmpty) return email;
  }
  return null;
}
