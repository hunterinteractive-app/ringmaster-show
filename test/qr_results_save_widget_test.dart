// Run with flutter test --platform chrome test/qr_results_save_widget_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final saves = <Map<String, dynamic>>[];
  var expired = false;
  var furChecks = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final path = request.url.path.split('/').last;
        Object response;
        var status = 200;
        if (path == 'save_results_entry') {
          final body = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          saves.add(body);
          if (expired) {
            status = 403;
            response = {
              'code': '42501',
              'message':
                  'This QR results link is locked. The 20-minute correction window after BOB has ended.',
            };
          } else {
            response = [
              {'id': 'entry', 'placement': 1, 'result_status': 'Shown'},
            ];
          }
        } else if (path == 'get_qr_fur_eligibility') {
          furChecks++;
          expect(jsonDecode(request.body)['p_entry_id'], 'entry');
          response = [
            {'entry_id': 'entry', 'blocked_reason': null},
          ];
        } else {
          fail('Unexpected QR request: $path');
        }
        return http.Response(
          jsonEncode(response),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    expired = false;
    saves.clear();
    furChecks = 0;
  });

  Future<void> openSheet(WidgetTester tester, {bool fur = false}) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = <String, dynamic>{
      'entry_id': 'entry',
      'section_id': 'section',
      'species': 'rabbit',
      'breed': 'Standard Chinchilla',
      'variety': 'Standard',
      'class_name': fur ? 'Fur / Wool' : 'Senior',
      'sex': 'Buck',
      'placement': '1',
      'result_status': 'Shown',
      'is_shown': true,
      'is_fur': fur,
      'tattoo': '67',
      '_awards': <String>[],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: AppTheme.surfaceTextScope(
              context,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => ResultsEntrySheet(
                      showId: 'show',
                      entry: entry,
                      classEntries: [entry],
                      judges: const [],
                      availablePlacements: const ['1'],
                      shownCount: 1,
                      currentIndex: 0,
                      totalCount: 1,
                      breedClassSystems: const {'standard chinchilla': 'four'},
                      finalAwardMode: 'bis_ris',
                      showsByGroup: false,
                      showsByVariety: false,
                      isFurOrWoolClass: fur,
                      writerName: 'Test Writer',
                      writerPhone: '3175550100',
                      isQrEntryMode: true,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('anonymous writer saves attribution and BOB', (tester) async {
    await openSheet(tester);
    expect(Supabase.instance.client.auth.currentSession, isNull);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Best of Breed'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves.last['p_is_qr_entry_mode'], true);
    expect(saves.last['p_result_entered_by_name'], 'Test Writer');
    expect(saves.last['p_result_entered_by_phone'], '3175550100');
    expect(saves.last['p_awards'], contains('BOB'));
    expect(find.byType(ResultsEntrySheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expired page shows server lock error without pretending save succeeded',
    (tester) async {
      expired = true;
      await openSheet(tester);
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('20-minute correction window'),
        findsOneWidget,
      );
      expect(find.byType(ResultsEntrySheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      expired = false;
    },
  );

  testWidgets('fur QR uses public eligibility check and separate result save', (
    tester,
  ) async {
    await openSheet(tester, fur: true);
    expect(furChecks, 1);
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves.last['p_is_qr_entry_mode'], true);
    expect(saves.last['p_awards'], isEmpty);
    expect(find.byType(ResultsEntrySheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
