import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/sweepstakes_report_pdf.dart';

void main() {
  const cavyReport = SweepstakesReportData(
    showId: 'show-id',
    breedName: 'Cavy',
    scope: 'OPEN',
    showLetter: 'A',
    ruleSource: 'NO_RESULTS',
    verificationStatus: 'VERIFIED',
    engineType: 'NO_RESULTS',
    rows: [],
    species: 'cavy',
  );

  test('does not claim no cavies were shown when scoring is empty', () {
    expect(
      sweepstakesNoResultsMessage(cavyReport, shownEntryCount: 36),
      '36 cavies were shown, but no sweepstakes points were calculated. '
      'Review the cavy scoring configuration and regenerate this report.',
    );
  });

  test('uses the genuine empty-show message when no cavies were shown', () {
    expect(
      sweepstakesNoResultsMessage(cavyReport, shownEntryCount: 0),
      'No cavies were shown in this Show.',
    );
  });
}
