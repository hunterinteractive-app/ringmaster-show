@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ringmaster_show/screens/admin/show_sanctions_dialog.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const recipient = 'reports@example.invalid';
  const club = 'English Spot Club';
  const sanctionId = 'club-sanction';
  const sectionId = 'open-a';
  const reportIds = {'sweepstakes': 2, 'breed-details': 4};
  const prompt = 'Generate and send English Spot Club reports?';
  var savedNumber = 'ES-OLD';
  var hasReports = false;
  var previews = 0;
  var preparations = 0;
  var polls = 0;
  var sends = 0;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://sanction-fixture.invalid',
      anonKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        Object data = [];
        switch (request.url.pathSegments.last) {
          case 'shows':
            data = {'is_locked': false, 'finalized_at': null};
          case 'show_sections':
            data = [
              {
                'id': sectionId,
                'kind': 'open',
                'letter': 'A',
                'display_name': 'Open A',
                'is_enabled': true,
                'sort_order': 0,
              },
            ];
          case 'breeds':
            data = [
              {'id': 'spot', 'name': 'English Spot', 'species': 'rabbit'},
            ];
          case 'breed_clubs':
            data = [
              {
                'id': 'club',
                'club_type': 'NATIONAL CLUB',
                'club_name': club,
                'breed_name': 'English Spot',
              },
            ];
          case 'breed_club_contacts':
            data = [
              {'breed_club_id': 'club', 'email': recipient},
            ];
          case 'show_sanctions':
            if (request.method == 'PATCH') {
              savedNumber =
                  jsonDecode(request.body)['sanction_number'] as String;
            }
            data = [
              {
                'id': sanctionId,
                'section_id': sectionId,
                'club_name': club,
                'breed_club_id': 'club',
                'breed_name': 'English Spot',
                'sanctioning_body': 'NATIONAL CLUB',
                'sanction_number': savedNumber,
              },
            ];
          case 'get_sanction_club_report_options':
            previews++;
            expect(jsonDecode(request.body)['p_changes'], {
              sanctionId: savedNumber,
            });
            if (hasReports) {
              data = [
                {
                  'club_name': club,
                  'recipient': recipient,
                  'sections': ['Open A'],
                  'sanction_ids': [sanctionId],
                  'report_count': reportIds.length,
                },
              ];
            }
          case 'prepare_sanction_club_reports':
            preparations++;
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload['p_changes'], {sanctionId: savedNumber});
            expect(payload['p_club_name'], club);
            expect(payload['p_recipient'], recipient);
            data = [
              for (final report in reportIds.entries)
                {'artifact_id': report.key, 'generation': report.value},
            ];
          case 'show_report_artifacts':
            polls++;
            data = [
              for (final report in reportIds.entries)
                {
                  'id': report.key,
                  'generation': report.value,
                  'is_current': true,
                  'artifact_status': polls == 1 && report.key == 'sweepstakes'
                      ? 'queued'
                      : 'generated',
                },
            ];
          case 'send-report-email':
            sends++;
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload['sanction_generations'], reportIds);
            expect(payload['artifact_ids'], reportIds.keys.toList());
            expect(payload['to'], recipient);
            data = {'ok': true, 'provider_message_id': 'mock-email'};
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  testWidgets('saving sanctions offers only eligible club reports on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ShowSanctionsDialog.open(
                context,
                showId: 'show',
                showName: 'Sample Show',
              ),
              child: const Text('Open sanctions'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sanctions'));
    await tester.pumpAndSettle();

    Future<void> save([String? number]) async {
      if (number != null) {
        final oldNumber = savedNumber;
        final cell = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == oldNumber,
        );
        await tester.ensureVisible(cell);
        await tester.enterText(cell, number);
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    await save('  ES-OLD ');
    expect(previews, 0);
    expect(find.text(prompt), findsNothing);

    await save('ES-FIRST');
    expect(previews, 1);
    expect(find.text(prompt), findsNothing);

    hasReports = true;
    await save('ES-SECOND');
    expect(savedNumber, 'ES-SECOND');
    expect(find.text(prompt), findsOneWidget);
    expect(find.text('2 PDFs for Open A'), findsOneWidget);
    expect(find.text('Send to $recipient'), findsOneWidget);
    expect(preparations, 0);
    await tester.tap(find.text('Save Only'));
    await tester.pumpAndSettle();
    expect(find.text(prompt), findsNothing);
    expect(savedNumber, 'ES-SECOND');
    expect(sends, 0);

    await save('ES-THIRD');
    await tester.tap(find.text('Generate & Send'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Generating reports (1 of 2 ready)…'), findsOneWidget);
    expect(sends, 0);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Saved. Club reports sent.'), findsOneWidget);
    expect(preparations, 1);
    expect(sends, 1);
  });
}
