import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/screens/admin/show_closeout_v2_preview.dart',
    ).readAsStringSync();
  });

  test('offers a single-report ARBA resend only after a prior send', () {
    expect(source, contains(".eq('report_name', 'arba_report')"));
    expect(source, contains('_arbaReportsHaveBeenSent'));
    expect(source, contains("'Email This ARBA Report Again'"));
    expect(
      source,
      contains(
        "_selectedReportName == 'arba_report' &&\n"
        '                  _selectedArtifact != null &&\n'
        '                  _isGenerated(_selectedArtifact!) &&\n'
        '                  _arbaReportsHaveBeenSent',
      ),
    );
  });

  test(
    'resends one artifact with the secretary message and forced delivery',
    () {
      final resendStart = source.indexOf(
        'Future<void> _emailSelectedArbaReportAgain()',
      );
      final resendEnd = source.indexOf(
        'Future<List<ReportArtifactSummary>> _emailArtifactsFor(',
        resendStart,
      );
      expect(resendStart, greaterThanOrEqualTo(0));
      expect(resendEnd, greaterThan(resendStart));
      final resendBody = source.substring(resendStart, resendEnd);

      expect(resendBody, contains('artifactIds: [artifact.id]'));
      expect(
        resendBody,
        contains('message: _additionalMessageController.text.trim()'),
      );
      expect(resendBody, contains('forceResend: true'));
    },
  );
}
