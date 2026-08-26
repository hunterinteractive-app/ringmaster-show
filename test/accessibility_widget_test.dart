import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/accessible_icon_button.dart';

void main() {
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

  test('login screen offers an accessibility support contact', () {
    final source = File('lib/screens/login_screen.dart').readAsStringSync();

    expect(source, contains('Accessibility help: support@ringmasterone.com'));
    expect(source, contains("path: 'support@ringmasterone.com'"));
  });

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
