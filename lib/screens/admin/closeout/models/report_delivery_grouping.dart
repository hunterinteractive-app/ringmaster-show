List<List<Map<String, dynamic>>> groupReportDeliveriesForDisplay(
  Iterable<Map<String, dynamic>> rows,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final providerId = (row['provider_message_id'] ?? '').toString().trim();
    final key = providerId.isNotEmpty
        ? 'provider:$providerId'
        : [
            'attempt',
            (row['recipient_email'] ?? '').toString().trim().toLowerCase(),
            (row['subject'] ?? '').toString().trim().toLowerCase(),
            (row['created_at'] ?? '').toString().trim(),
          ].join('|');
    grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
  }
  return grouped.values.toList();
}
