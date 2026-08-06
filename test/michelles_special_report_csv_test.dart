import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/csv/builders/michelles_special_report_csv.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/other/michelles_special_report_data.dart';

void main() {
  test('includes the show exhibitor number in the 4-H check-in CSV', () async {
    final file = await MichellesSpecialReportCsvBuilder().buildFile(
      const MichellesSpecialReportData(
        showName: 'Westmoreland Fair',
        rows: [
          {
            'exhibitor_number': 2930,
            'exhibitor_name': 'Alex Exhibitor',
            'entered_animal_count': 2,
          },
        ],
      ),
      ReportRequest(
        showId: 'show-id',
        reportName: 'michelles_special_report',
        finalizeRunId: 'run-id',
      ),
    );

    final csv = utf8.decode(file.bytes).replaceFirst('\ufeff', '');
    expect(
      csv,
      contains(
        '"Exhibitor Number","Exhibitor Full Name","Number of Entered Animals"',
      ),
    );
    expect(csv, contains('"2930","Alex Exhibitor","2","",""'));
  });
}
