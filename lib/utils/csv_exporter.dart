// lib/utils/csv_exporter.dart
import 'csv_exporter_stub.dart'
    if (dart.library.html) 'csv_exporter_web.dart';

/// Exports CSV bytes with a suggested filename.
/// - Web: triggers a browser download.
/// - Desktop: opens Save dialog and writes the file.
/// Returns a human-readable message (for SnackBar), or null if user cancelled.
Future<String?> exportCsvBytes({
  required List<int> bytes,
  required String suggestedName,
}) {
  return exportCsvBytesImpl(bytes: bytes, suggestedName: suggestedName);
}