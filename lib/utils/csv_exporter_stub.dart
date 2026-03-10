// lib/utils/csv_exporter_stub.dart
import 'package:file_selector/file_selector.dart';

Future<String?> exportCsvBytesImpl({
  required List<int> bytes,
  required String suggestedName,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'CSV', extensions: ['csv']),
    ],
  );

  if (location == null) return null; // user cancelled

  final file = XFile.fromData(
    bytes,
    mimeType: 'text/csv',
    name: suggestedName,
  );

  await file.saveTo(location.path);
  return 'CSV exported: ${location.path}';
}