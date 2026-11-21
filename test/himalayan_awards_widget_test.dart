// Run with flutter test --platform chrome.
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
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path.split('/').last, 'save_results_entry');
        saves.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
        return http.Response(
          '[{"id":"entry"}]',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(saves.clear);

  Future<void> open(
    WidgetTester tester,
    String age, {
    bool qr = true,
    Map<String, dynamic>? other,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = <String, dynamic>{
      'entry_id': 'entry',
      'section_id': 'open-a',
      'species': 'rabbit',
      'breed': 'Himalayan',
      'variety': 'Black',
      'class_name': age,
      'sex': 'Buck',
      'uses_variety_awards': true,
      'uses_group_awards': false,
      'is_national_show': false,
      'placement': '1',
      'result_status': 'Shown',
      'is_shown': true,
      'tattoo': 'HIM-1',
      '_awards': <String>[],
    };
    final rows = [
      entry,
      if (other != null) {...entry, 'entry_id': 'other', ...other},
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => qr
                    ? ResultsEntrySheet.qrAwards(
                        showId: 'show',
                        entry: entry,
                        breedEntries: rows,
                        judges: const [],
                        breedClassSystems: const {'himalayan': 'four'},
                        finalAwardMode: 'bis_ris',
                        writerName: 'Test Writer',
                        writerPhone: '3175550100',
                        awardCodes: const {'BJV', 'BSV', 'BJB', 'BSB'},
                      )
                    : ResultsEntrySheet(
                        showId: 'show',
                        entry: entry,
                        classEntries: rows,
                        judges: const [],
                        availablePlacements: const ['1'],
                        shownCount: 1,
                        currentIndex: 0,
                        totalCount: 1,
                        breedClassSystems: const {'himalayan': 'four'},
                        finalAwardMode: 'bis_ris',
                        showsByGroup: false,
                        showsByVariety: true,
                        isFurOrWoolClass: false,
                        isQrEntryMode: true,
                        writerName: 'Test Writer',
                        writerPhone: '3175550100',
                      ),
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

  Future<void> select(WidgetTester tester, String label) async {
    final tile = find.widgetWithText(CheckboxListTile, label);
    expect(tile, findsOneWidget);
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  for (final qr in [false, true]) {
    for (final age in ['Junior', 'Senior']) {
      testWidgets(
        '${qr ? 'QR awards' : 'results sheet'} saves Himalayan $age variety and breed awards on an ordinary show',
        (tester) async {
          await open(tester, age, qr: qr);
          await select(tester, 'Best $age Variety');
          await select(tester, 'Best $age of Breed');
          await save(tester);
          expect(
            saves.single['p_awards'],
            containsAll(age == 'Junior' ? ['BJV', 'BJB'] : ['BSV', 'BSB']),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final age in ['Junior', 'Senior']) {
    final code = age == 'Junior' ? 'BJV' : 'BSV';
    testWidgets(
      '$age variety winner is unique across sexes in the same variety',
      (tester) async {
        await open(
          tester,
          age,
          other: {
            'sex': 'Doe',
            '_awards': [code],
          },
        );
        await select(tester, 'Best $age Variety');
        await save(tester);
        expect(saves, isEmpty);
        expect(
          find.text('$code is already assigned for this variety.'),
          findsOneWidget,
        );
      },
    );
    for (final override in [
      {'variety': 'Blue'},
      {'section_id': 'youth-a'},
    ]) {
      testWidgets('$age variety winner remains independent for $override', (
        tester,
      ) async {
        await open(
          tester,
          age,
          other: {
            ...override,
            '_awards': [code],
          },
        );
        await select(tester, 'Best $age Variety');
        await save(tester);
        expect(saves.single['p_awards'], [code]);
      });
    }
  }
}
