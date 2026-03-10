// lib/utils/csv_exporter_web.dart
import 'dart:html' as html;

Future<String?> exportCsvBytesImpl({
  required List<int> bytes,
  required String suggestedName,
}) async {
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', suggestedName)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();

  html.Url.revokeObjectUrl(url);

  return 'CSV downloaded.';
}