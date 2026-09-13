import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/legal/legal_agreement_dialog.dart';
import 'package:ringmaster_show/screens/legal/privacy_policy_screen.dart';
import 'package:ringmaster_show/screens/legal/terms_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/accessible_icon_button.dart';

Future<void> _openLegalAgreement(
  WidgetTester tester, {
  ValueChanged<bool?>? onResult,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => const LegalAgreementDialog(),
              );
              onResult?.call(result);
            },
            child: const Text('Open agreement'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open agreement'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('legal agreement has readable text before and after checking', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    bool? result;
    await _openLegalAgreement(tester, onResult: (value) => result = value);

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tester.tap(find.text('Agree & Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalAgreementDialog), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Agree & Continue'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    semantics.dispose();
  });

  testWidgets(
    'legal agreement keeps its choice while reviewing either policy',
    (tester) async {
      bool? result;
      await _openLegalAgreement(tester, onResult: (value) => result = value);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();

      for (final entry in {
        'View Terms of Service': TermsScreen,
        'View Privacy Policy': PrivacyPolicyScreen,
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.byType(entry.value), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isTrue,
        );
      }
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );

  testWidgets('legal agreement fits a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openLegalAgreement(tester, textScale: 1.5);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(find.text('Agree & Continue').hitTestable(), findsOneWidget);
  });

  testWidgets('accessible icon button exposes a named button action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccessibleIconButton(
            tooltip: 'Approve and apply request',
            icon: const Icon(Icons.check),
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(AccessibleIconButton)),
      matchesSemantics(
        label: 'Approve and apply request',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  test(
    'page shell header does not restrict titles or subtitles to one line',
    () {
      final source = File(
        'lib/widgets/ringmaster_page_shell.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('maxLines: 1')));
      expect(source, isNot(contains('overflow: TextOverflow.ellipsis')));
    },
  );

  test('audited icon-only controls have accessible names', () {
    const paths = [
      'lib/screens/admin/show_checkin_activity_screen.dart',
      'lib/screens/admin/show_checkin_dashboard_screen.dart',
      'lib/screens/admin/show_checkin_roster_screen.dart',
      'lib/screens/admin/show_fees_dialog.dart',
      'lib/screens/login_screen.dart',
    ];

    for (final path in paths) {
      expect(File(path).readAsStringSync(), contains('tooltip:'));
    }

    final checkinDashboard = File(
      'lib/screens/admin/show_checkin_dashboard_screen.dart',
    ).readAsStringSync();
    expect(checkinDashboard, contains('Check-in actions for'));
  });

  test('critical inline status messages are announced', () {
    const paths = [
      'lib/widgets/animal_editor/animal_editor_dialog.dart',
      'lib/screens/admin/admin_entry_management_screen.dart',
      'lib/screens/admin/results/admin_results_entry_screen.dart',
      'lib/screens/exhibitor_checkin_portal_screen.dart',
      'lib/screens/square_payment_return_screen.dart',
    ];

    for (final path in paths) {
      expect(File(path).readAsStringSync(), contains('liveRegion: true'));
    }
  });

  test(
    'animal entry controls include animal context for assistive technology',
    () {
      final source = File(
        'lib/screens/enter_show_screen.dart',
      ).readAsStringSync();

      expect(source, contains("label: 'Select \${_displayAnimalTitle(a)}'"));
      expect(source, contains("label: 'Class for \${_displayAnimalTitle(a)}'"));
    },
  );

  test(
    'login screen links to the accessibility statement and support contact',
    () {
      final loginSource = File(
        'lib/screens/login_screen.dart',
      ).readAsStringSync();
      final statementSource = File(
        'lib/screens/legal/accessibility_statement_screen.dart',
      ).readAsStringSync();

      expect(loginSource, contains('Accessibility Statement'));
      expect(loginSource, contains('AccessibilityStatementScreen'));
      expect(statementSource, contains('WCAG) 2.2 Level AA'));
      expect(statementSource, contains('support@ringmasterone.com'));
    },
  );

  test(
    'dense data and picker controls retain keyboard and reflow guidance',
    () {
      final entryManagement = File(
        'lib/screens/admin/admin_entry_management_screen.dart',
      ).readAsStringSync();
      final entriesTable = File(
        'lib/screens/admin/entries_by_breed_section_table.dart',
      ).readAsStringSync();
      final paybackSettings = File(
        'lib/screens/admin/payback_settings_dialog.dart',
      ).readAsStringSync();

      expect(
        'AutocompleteHighlightedOption.of('.allMatches(entryManagement).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        entriesTable,
        contains('Scroll horizontally to view all columns.'),
      );
      expect(
        paybackSettings,
        contains('Scroll horizontally to view all table columns.'),
      );
    },
  );

  test('queued closeout PDFs include descriptive document metadata', () {
    final builders = Directory(
      'lib/screens/admin/closeout/pdf/builders',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.dart'));

    for (final builder in builders) {
      final source = builder.readAsStringSync();
      if (!source.contains('pw.Document(')) continue;

      expect(source, contains('title:'));
      expect(source, contains("author: 'RingMaster Show'"));
      expect(source, contains('subject:'));
    }
  });
}
