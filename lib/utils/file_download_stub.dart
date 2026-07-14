import 'dart:typed_data';

Future<void> downloadFileBytes(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError('Browser file downloads require Flutter web.');
}
