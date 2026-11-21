import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final writes = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object? body = [];
        if (path.endsWith('/functions/v1/send-report-email')) {
          writes.add(
            Map<String, dynamic>.from(jsonDecode(request.body) as Map),
          );
          body = {'ok': true, 'provider_message_id': 'mock-only'};
        } else if (path.endsWith('/show_report_artifacts') &&
            request.method == 'GET') {
          Map<String, dynamic> artifact(
            String scope,
            String name, {
            String club = 'State Club',
            String email = 'state@example.test',
            String status = 'generated',
            String sanction = 'STATE CLUB',
          }) => {
            'id': '$scope-$name',
            'show_id': 'show-1',
            'report_name': name,
            'artifact_status': status,
            'is_current': true,
            'storage_bucket': 'reports',
            'storage_path': '$scope-$name.pdf',
            'generated_at': '2026-11-17T20:00:00Z',
            'metadata': {
              'scope': scope,
              'show_letter': 'A',
              'club_name': club,
              'sanctioning_body': sanction,
              'sweepstakes_email': email,
            },
          };
          body = [
            for (final scope in ['OPEN', 'YOUTH'])
              for (final name in [
                'details_by_breed',
                'exh_by_breed',
                'best_display_report',
              ])
                artifact(scope, name),
            artifact('OPEN', 'details_by_breed', club: 'Other club'),
            artifact('OPEN', 'details_by_breed', email: 'other@example.test'),
            artifact('OPEN', 'details_by_breed', status: 'failed'),
            artifact('OPEN', 'details_by_breed', sanction: 'NATIONAL CLUB'),
          ];
        } else if (path.endsWith('/shows')) {
          body = {
            'id': 'show-1',
            'name': 'Synthetic Show',
            'created_by': 'owner',
            'is_locked': false,
            'finalized_at': null,
            'start_date': '2026-11-17',
            'end_date': '2026-11-17',
          };
        } else if (path.endsWith('/show_sections')) {
          body = [
            {
              'id': 'section-1',
              'show_id': 'show-1',
              'kind': 'open',
              'letter': 'A',
              'is_enabled': true,
              'sort_order': 1,
            },
          ];
        } else if (path.endsWith('/show_arba_report_details')) {
          body = null;
        } else if (path.contains('/rpc/')) {
          if (path.contains('can_access')) body = false;
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  testWidgets('state Email All Shows confirms and sends six current files', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'closeout_v2_report_selection_show-1': jsonEncode({
        'group': 'club',
        'report_name': 'best_display_report',
        'club_name': 'State Club',
        'scope': 'YOUTH',
        'show_letter': 'A',
      }),
    });
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: const ShowCloseoutV2PreviewPage(
          showId: 'show-1',
          showName: 'Synthetic Show',
          canFinalizeShow: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final singleButton = find.text('Email This Show');
    await tester.scrollUntilVisible(
      singleButton,
      500,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(singleButton);
    await tester.pumpAndSettle();
    await tester.tap(singleButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This will send 1 generated report file'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    final button = find.text('Email All Shows');
    await tester.scrollUntilVisible(
      button,
      500,
      maxScrolls: 30,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This will send 6 generated report files'),
      findsOneWidget,
    );
    expect(find.textContaining('OPEN A —'), findsOneWidget);
    expect(find.textContaining('YOUTH A —'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    final theme = Theme.of(tester.element(dialog));
    final foreground = theme.dialogTheme.contentTextStyle!.color!;
    final background = theme.dialogTheme.backgroundColor!;
    final a = foreground.computeLuminance(), b = background.computeLuminance();
    expect((b + .05) / (a + .05), greaterThanOrEqualTo(4.5));
    expect(tester.takeException(), isNull);
    expect(writes, isEmpty);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'Secretary note alone is not a resend.',
    );
    await tester.tap(find.text('Send Email'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .text('Reports sent to state@example.test.')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    expect(
      writes.single['artifact_ids'],
      unorderedEquals([
        for (final scope in ['OPEN', 'YOUTH'])
          for (final name in [
            'details_by_breed',
            'exh_by_breed',
            'best_display_report',
          ])
            '$scope-$name',
      ]),
    );
    expect(
      writes.single['subject'],
      'Synthetic Show - State Club Reports - All Shows',
    );
    expect(writes.single['to'], 'state@example.test');
    expect(writes.single['force_resend'], isFalse);
    expect(writes.single['message'], 'Secretary note alone is not a resend.');
    expect(find.text('Reports sent to state@example.test.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
