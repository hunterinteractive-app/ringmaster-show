import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/json/builders/sweepstakes_json_export.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/breed_results_detail_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart';

void main() {
  test('produces a versioned, per-breed JSON export', () {
    final result = const SweepstakesJsonExport().buildFile(
      request: ReportRequest(
        showId: 'show-id',
        reportName: 'sweepstakes_json_export',
        finalizeRunId: 'run-id',
        showName: 'Fiber Festival',
        showDate: '2026-07-18',
      ),
      results: const BreedResultsDetailReportData(
        showId: 'show-id',
        breedName: 'Czech Frosty',
        species: 'rabbit',
        scope: 'OPEN',
        showLetter: 'A',
        judgeName: 'Judge Example',
        breedSanctionNumber: 'CLUB-1',
        breedAwards: [
          BreedAward(
            award: 'Best of Breed',
            animal: 'FROST',
            className: 'Senior',
            exhibitorName: 'Alex Example',
            animalsJudged: 9,
            exhibitorsJudged: 3,
          ),
        ],
        varieties: [],
      ),
      sweepstakes: const SweepstakesReportData(
        showId: 'show-id',
        breedName: 'Czech Frosty',
        scope: 'OPEN',
        showLetter: 'A',
        ruleSource: 'CLUB',
        verificationStatus: 'VERIFIED',
        engineType: 'STANDARD',
        rows: [
          SweepstakesReportRow(
            rank: 1,
            exhibitorName: 'Alex Example',
            exhibitorAddress: '123 Example Road',
            classPoints: 10,
            arbaClassPoints: 0,
            varietyPoints: 0,
            groupPoints: 0,
            bobPoints: 5,
            bisPoints: 0,
            furPoints: 0,
            totalPoints: 15,
          ),
        ],
      ),
    );

    final json = jsonDecode(utf8.decode(result.bytes)) as Map<String, dynamic>;
    expect(result.mimeType, 'application/json');
    expect(result.fileName, endsWith('_Sweepstakes.json'));
    expect(json['format'], 'ringmaster.sweepstakes_results');
    expect(json['version'], 1);
    expect(json['breed'], 'Czech Frosty');
    expect((json['show'] as Map)['letter'], 'A');
    expect((json['sweepstakes'] as Map)['exhibitors'], hasLength(1));
  });
}
