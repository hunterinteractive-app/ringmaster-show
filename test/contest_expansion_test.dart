import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/models/contest_settings.dart';
import 'package:ringmaster_show/models/contest_template.dart';
import 'package:ringmaster_show/models/show_addon.dart';
import 'package:ringmaster_show/screens/show_addons_screen.dart';
import 'package:ringmaster_show/services/contest_report_service.dart';
import 'package:ringmaster_show/widgets/contests/contest_result_dialog.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  test(
    'templates are independent editable drafts and Royalty remains Individual',
    () {
      expect(ContestTemplate.royalty.group, 'Individual');
      expect(
        ContestTemplate.royalty.createDraft().contest.entryType,
        'individual',
      );
      for (final template in ContestTemplate.values) {
        final a = template.createDraft(), b = template.createDraft();
        expect(a.contest.validate(a.divisions), isNull, reason: template.title);
        expect(a.id, isNot(b.id));
        a.contest.data['categories'] = ['Changed'];
        expect(b.contest.categories, isNot(contains('Changed')));
        expect(a.useShowEntryDates, isTrue);
        expect(a.registrationOpenAt, isNull);
      }
    },
  );
  test('age cutoff and conditional form validation handle boundaries', () {
    expect(
      ContestSettings.ageOn(DateTime(2015, 9, 16), DateTime(2026, 9, 15)),
      10,
    );
    expect(
      ContestSettings.ageOn(DateTime(2015, 9, 16), DateTime(2026, 9, 16)),
      11,
    );
    expect(ContestSettings.date('2025-02-29'), isNull);
    final field = ContestField(
      label: 'Application',
      type: 'file',
      required: true,
      onlyDivision: 'Senior',
    );
    expect(field.visibleFor('', 'Junior'), isFalse);
    expect(field.visibleFor('', 'Senior'), isTrue);
    expect(field.validate(null), isNotNull);
    expect(field.validate({'path': 'a/b/c.pdf'}), isNull);
    final choices = ContestField(
      label: 'Interests',
      type: 'multi_select',
      options: ['A', 'B'],
      required: true,
    );
    expect(choices.validate(['A', 'B']), isNull);
    expect(choices.validate(['A', 'A']), isNotNull);
    expect(choices.validate(['Unknown']), isNotNull);
  });
  test(
    'winner reports contain roster names but exclude private answers and contact information',
    () {
      final rows = ContestReportService.rows([
        {
          'name': 'Royalty',
          'exhibitor_name': 'Sample Youth',
          'exhibitor_number': '42',
          'email': 'private@example.invalid',
          'division': 'Junior',
          'answers': {
            'medical': 'PRIVATE',
            'file': {'path': 'private/file.pdf'},
          },
          'registration_data': {
            'birthdate': '2015-01-01',
            'team': {
              'name': 'Team A',
              'members': [
                {'name': 'Member A', 'birthdate': '2014-01-01'},
              ],
            },
          },
          'result': {
            'status': 'recorded',
            'place': 1,
            'awards': ['Champion'],
          },
        },
      ], 'results');
      final csv = utf8.decode(ContestReportService.csv(rows));
      expect(csv, contains('Champion'));
      expect(csv, contains('Team A'));
      expect(csv, contains('Member A'));
      expect(rows[0].length, rows[1].length);
      for (final private in [
        'private@example.invalid',
        'PRIVATE',
        'private/file.pdf',
        '2015-01-01',
        '2014-01-01',
      ]) {
        expect(csv, isNot(contains(private)));
      }
      expect(ContestReportService.csvCell('=1+1'), contains("'=1+1"));
      expect(ContestReportService.csvCell('a,"b"'), '"a,""b"""');
    },
  );
  Future<void> visible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> mobile(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('project form shows only questions for chosen category', (
    tester,
  ) async {
    await mobile(
      tester,
      AddonEntryDialog(
        item: ShowAddon(
          kind: 'contest',
          name: 'Projects',
          contestSettings: ContestSettings({
            'entry_type': 'project',
            'categories': ['Art', 'Photo'],
          }),
          fields: [
            ContestField(
              id: 'art',
              label: 'Medium',
              required: true,
              onlyCategory: 'Art',
            ),
            ContestField(id: 'photo', label: 'Camera', onlyCategory: 'Photo'),
          ],
        ),
        currency: 'usd',
      ),
    );
    expect(find.text('Medium *'), findsNothing);
    await visible(
      tester,
      find.widgetWithText(DropdownButtonFormField<String>, 'Category *'),
    );
    await visible(tester, find.text('Art').last);
    expect(find.text('Medium *'), findsOneWidget);
    expect(find.text('Camera (optional)'), findsNothing);
    await visible(tester, find.text('Add to Cart'));
    expect(find.text('Enter Project title.'), findsOneWidget);
    expect(find.text('Medium is required.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'team registration requires roster and coordinator authorization',
    (tester) async {
      await mobile(
        tester,
        AddonEntryDialog(
          item: ShowAddon(
            kind: 'contest',
            name: 'Team Judging',
            contestSettings: ContestSettings({
              'entry_type': 'team',
              'team_min': 2,
              'team_max': 3,
            }),
          ),
          currency: 'usd',
        ),
      );
      await visible(tester, find.text('Add to Cart'));
      expect(
        find.text('Check the number of active members and alternates.'),
        findsOneWidget,
      );
      expect(
        find.text('Confirm you are authorized to enter this team.'),
        findsOneWidget,
      );
      await visible(tester, find.text('Add Team Member'));
      expect(find.text('Member 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('result correction requires a reason; no scoring fields', (
    tester,
  ) async {
    await mobile(
      tester,
      ContestResultDialog(
        row: {
          'exhibitor_name': 'Sample',
          'result': {
            'status': 'recorded',
            'place': 1,
            'awards': ['Champion'],
          },
        },
        settings: ContestSettings({
          'places': 3,
          'awards': [
            {'name': 'Champion', 'recipients': 1},
          ],
        }),
      ),
    );
    expect(find.textContaining('Score'), findsNothing);
    await visible(tester, find.text('Save Result'));
    expect(find.text('Enter the reason for this correction.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
