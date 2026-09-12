import 'dart:io';
import 'package:test/test.dart';
import 'package:ringmaster_show/reporting_core/assets/file_system_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/judge/judge_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/judge_report_pdf.dart';

void main() {
  test(
    '110-judge overview advances across pages and finishes within its deadline',
    () async {
      final data = JudgeReportData(
        show: JudgeReportShowInfo(
          showId: 'synthetic',
          showName: 'National PDF regression',
        ),
        generatedAt: DateTime.utc(2026, 9, 10),
        judges: List.generate(
          110,
          (i) => JudgeReportJudge(
            judgeId: 'judge-$i',
            displayName: 'Judge $i',
            arbaNumber: 'LOCAL-$i',
            rows: List.generate(
              56,
              (j) => JudgeReportRow(
                entryId: '$i-$j',
                sectionLabel: 'Open A',
                species: 'rabbit',
                breed: 'Breed $j',
                variety: 'Variety',
                className: 'Senior',
                sex: 'Buck',
                tattoo: '$i-$j',
                exhibitorName: 'Synthetic Exhibitor',
              ),
            ),
          ),
        ),
      );
      final builder = JudgeReportPdfBuilder(
        assets: FileSystemReportAssetLoader(Directory('../../assets')),
      );
      final bytes = await builder
          .build(data)
          .timeout(const Duration(seconds: 15));
      expect(bytes.take(5).toList(), '%PDF-'.codeUnits);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
