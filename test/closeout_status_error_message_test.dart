import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/services/closeout_status_error_message.dart';

void main() {
  test('replaces the production Postgres timeout with secretary-safe copy', () {
    const raw =
        'PostgrestException(message: canceling statement due to statement '
        'timeout, code: 57014, details: , hint: null)';

    expect(isCloseoutStatusStatementTimeout(raw), isTrue);
    expect(
      closeoutReportStatusErrorMessage(raw),
      closeoutReportStatusTimeoutMessage,
    );
    expect(closeoutReportStatusErrorMessage(raw), isNot(contains('57014')));
    expect(
      closeoutReportStatusErrorMessage(raw),
      isNot(contains('PostgrestException')),
    );
  });

  test('detects timeout code even when the message wording changes', () {
    expect(
      closeoutReportStatusErrorMessage('database request failed, code=57014'),
      closeoutReportStatusTimeoutMessage,
    );
  });

  test('leaves unrelated status errors available for diagnosis', () {
    const raw = 'Permission denied';
    expect(closeoutReportStatusErrorMessage(raw), raw);
  });

  test('sanitizes timeout errors throughout the closeout workflow', () {
    final source = File(
      'lib/screens/admin/show_closeout_v2_preview.dart',
    ).readAsStringSync();

    String classBody(String start, String end) {
      final startIndex = source.indexOf(start);
      final endIndex = source.indexOf(end, startIndex);
      expect(startIndex, greaterThanOrEqualTo(0));
      expect(endIndex, greaterThan(startIndex));
      return source.substring(startIndex, endIndex);
    }

    final protectedLoaders = <String>[
      classBody(
        'class _ArbaDetailsPreviewPanelState',
        'class _ArbaPreviewTextField',
      ),
      classBody('class _MustFixPanelState', 'class _ResultsReadinessIssue'),
      classBody('class _ReviewWarningsPanelState', 'class _CloseoutWarning'),
      classBody(
        'class _FinancialPayoutReviewPanelState',
        'class _FinancialTotalGrid',
      ),
      classBody(
        'class _GenerateReportsPanelState',
        'class _GenerationProgressPanel',
      ),
      classBody('class _PublishResultsPanelState', 'class _PublishTargetTile'),
      classBody('class _DeliveryStatusPanelState', 'class _DeliveryTile'),
      classBody(
        'class _FinalCloseoutPreviewPanelState',
        'class _FinalCloseoutReadiness',
      ),
      classBody(
        'class _LiveReportDownloadsState',
        'class _SelectedReportStatus',
      ),
    ];

    for (final loader in protectedLoaders) {
      expect(
        RegExp(r'closeoutReportStatusErrorMessage\(').allMatches(loader).length,
        greaterThanOrEqualTo(2),
      );
      expect(loader, isNot(contains('_error = error.toString();')));
    }
  });
}
