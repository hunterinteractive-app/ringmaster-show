import 'dart:convert';

import '../../models/base/report_file_result.dart';
import '../../models/base/report_request.dart';
import '../../models/other/michelles_special_report_data.dart';

class MichellesSpecialReportCsvBuilder {
  Future<ReportFileResult> buildFile(
    MichellesSpecialReportData data,
    ReportRequest request,
  ) async {
    final rows = <List<String>>[
      const [
        'Exhibitor Full Name',
        'Number of Entered Animals',
        'Project Book Verified',
        'Vet Check Completed',
      ],
      ...data.rows.map(
        (row) => [
          (row['exhibitor_name'] ?? '').toString(),
          (row['entered_animal_count'] ?? 0).toString(),
          '',
          '',
        ],
      ),
    ];

    final csv = rows.map((row) => row.map(_escape).join(',')).join('\r\n');
    final showName = _safeFileName(data.showName);

    return ReportFileResult(
      fileName: '4-H Check in${showName.isEmpty ? '' : ' - $showName'}.csv',
      mimeType: 'text/csv',
      bytes: utf8.encode('\ufeff$csv\r\n'),
    );
  }

  String _escape(String value) => '"${value.replaceAll('"', '""')}"';

  String _safeFileName(String value) => value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
      .replaceAll(RegExp(r'\s+'), ' ');
}
