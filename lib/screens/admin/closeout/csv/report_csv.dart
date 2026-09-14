import 'dart:convert';

import '../models/base/report_file_result.dart';

/// One rectangular table, with no repeated headings or PDF page furniture.
class ReportCsvTable {
  const ReportCsvTable(this.headers, this.rows);

  final List<String> headers;
  final List<List<Object?>> rows;

  ReportFileResult toFile({
    required String title,
    required String showName,
    String? scopeLabel,
  }) {
    final csv = StringBuffer('\ufeff');
    void writeRow(List<Object?> row) {
      csv.write('${row.map(_cell).join(',')}\r\n');
    }

    // Include context as columns so sorting/filtering never separates it.
    writeRow(['Show', ...headers]);
    for (final row in rows) {
      if (row.length != headers.length) {
        throw StateError('CSV row does not match its column headings.');
      }
      writeRow([showName, ...row]);
    }
    final name =
        [title, showName, if (scopeLabel?.isNotEmpty == true) scopeLabel!]
            .where((part) => part.isNotEmpty)
            .join(' - ')
            .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]+'), '-')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    return ReportFileResult(
      fileName: '$name.csv',
      mimeType: 'text/csv;charset=utf-8',
      bytes: utf8.encode(csv.toString()),
      metadata: {'row_count': rows.length},
    );
  }

  static String _cell(Object? value) {
    var text = value?.toString() ?? '';
    // Quoting alone does not stop spreadsheet applications executing text.
    // Actual numbers (including negative amounts) remain numeric.
    if (value is String && RegExp(r'^[\s\x00-\x1f]*[=+@-]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
