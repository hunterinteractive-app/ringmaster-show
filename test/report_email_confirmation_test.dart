import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/widgets/report_email_confirmation.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  ReportEmailConfirmation? result;
  Future<void> open(
    WidgetTester tester, {
    bool bulk = true,
    String note = '',
  }) async {
    result = null;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showReportEmailConfirmation(
                context,
                title: 'Send Club Reports?',
                description: 'Send all generated club reports.',
                initialMessage: note,
                bulk: bulk,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('normal send with a note never silently requests a resend', (
    tester,
  ) async {
    await open(tester, note: 'Thank you for attending.');
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('Send Email'));
    await tester.pumpAndSettle();
    expect(result!.forceResend, isFalse);
    expect(result!.message, 'Thank you for attending.');
  });
  testWidgets(
    'bulk resend needs explicit selection and a nonblank message at phone width',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Resend reports already sent'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Resend Reports'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(
        find.text(
          'Add a message explaining why these reports are being resent.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final theme = Theme.of(tester.element(find.byType(AlertDialog)));
      final background = theme.dialogTheme.backgroundColor!;
      for (final foreground in [
        theme.dialogTheme.contentTextStyle!.color!,
        theme.inputDecorationTheme.errorStyle!.color!,
      ]) {
        expect(
          (background.computeLuminance() + .05) /
              (foreground.computeLuminance() + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
      await tester.enterText(
        find.byType(TextField),
        ' Corrected exhibitor names. ',
      );
      await tester.tap(find.text('Resend Reports'));
      await tester.pumpAndSettle();
      expect(result!.forceResend, isTrue);
      expect(result!.message, 'Corrected exhibitor names.');
    },
  );
  testWidgets(
    'cancel sends nothing and single resend remains an explicit choice',
    (tester) async {
      await open(tester, bulk: false);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resend reports already sent'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resend Reports'));
      await tester.pumpAndSettle();
      expect(result!.forceResend, isTrue);
    },
  );
}
