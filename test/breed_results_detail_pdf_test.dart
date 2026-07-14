import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/reporting_core/assets/flutter_report_asset_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_results_detail_report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ClassEntry entry(String animal, String sex, String variety, double points) =>
      ClassEntry(
        place: '1',
        animal: animal,
        exhibitorName: 'Sample Exhibitor',
        sex: sex,
        variety: variety,
        pointsEarned: points,
      );

  ClassSection classSection(String age, String sex, String variety) =>
      ClassSection(
        className: age,
        entryCount: 2,
        placedCount: 1,
        animalsJudged: 2,
        exhibitorsJudged: 2,
        rows: [entry('$variety $age $sex', sex, variety, 7)],
      );

  VarietySection variety(String name) => VarietySection(
    varietyName: name,
    awards: [
      BreedAward(
        award: 'BOV',
        animal: '$name BOV Winner',
        className: 'Senior',
        exhibitorName: 'Sample Exhibitor',
        sex: 'Buck',
        variety: name,
        animalsJudged: 6,
        exhibitorsJudged: 4,
        pointsEarned: 12,
      ),
    ],
    sexSections: [
      SexSection(
        sexLabel: 'Bucks',
        classes: [
          classSection('Junior', 'Buck', name),
          classSection('Intermediate', 'Buck', name),
          classSection('Senior', 'Buck', name),
        ],
      ),
      SexSection(
        sexLabel: 'Does',
        classes: [
          classSection('Junior', 'Doe', name),
          classSection('Intermediate', 'Doe', name),
          classSection('Senior', 'Doe', name),
        ],
      ),
    ],
  );

  test('regenerates the Mini Rex layout review PDF', () async {
    final fur = VarietySection(
      varietyName: 'White',
      awards: const [],
      sexSections: [
        SexSection(
          sexLabel: '',
          classes: [
            ClassSection(
              className: 'Fur',
              entryCount: 1,
              placedCount: 1,
              animalsJudged: 1,
              exhibitorsJudged: 1,
              rows: [
                ClassEntry(
                  place: '1',
                  animal: 'White Fur Winner',
                  exhibitorName: 'Sample Exhibitor',
                  variety: 'White',
                  pointsCategory: 'White',
                  pointsEarned: 5,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    final data = BreedResultsDetailReportData(
      showId: 'sample-show',
      breedName: 'Mini Rex',
      species: 'rabbit',
      scope: 'OPEN',
      showLetter: 'A',
      judgeName: 'Sample Judge',
      hostClubName: 'Sample Club',
      breedAwards: const [],
      varieties: [
        variety('Black'),
        variety('Blue'),
        variety('Tortoise'),
        variety('Castor'),
        variety('Otter'),
        variety('Broken'),
        fur,
      ],
    );
    final request = ReportRequest(
      showId: 'sample-show',
      reportName: 'breed_results_detail_report',
      finalizeRunId: 'sample-run',
      breedName: 'Mini Rex',
      species: 'rabbit',
      scope: 'OPEN',
      showLetter: 'A',
      showName: 'Mini Rex Layout Review',
      showDate: 'July 14, 2026',
    );

    final result = await BreedResultsDetailReportPdf(
      assets: const FlutterReportAssetLoader(),
    ).buildFile(data, request);
    final output = File(
      'build/review/Mini_Rex_Breed_Results_Detail_Report_layout_review.pdf',
    );
    await output.parent.create(recursive: true);
    await output.writeAsBytes(result.bytes);

    expect(result.mimeType, 'application/pdf');
    expect(result.bytes.length, greaterThan(1000));
    expect(await output.exists(), isTrue);
  });
}
