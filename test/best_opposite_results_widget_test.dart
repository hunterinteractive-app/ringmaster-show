import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';
// Run with flutter test --platform chrome.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';
import 'package:ringmaster_show/services/final_award_format.dart';

void main() {
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
        final path = request.url.path.split('/').last;
        final Object response = switch (path) {
          'shows' => {'final_award_mode': bestOppositeFinalAwardMode},
          'show_arba_report_details' ||
          'show_closeout_state' => <String, dynamic>{},
          'show_sections' => [
            {
              'id': 'open-a',
              'kind': 'open',
              'letter': 'A',
              'display_name': 'Open A',
            },
          ],
          'show_results_blocking_entry_issues_scoped' => {'items': []},
          'show_results_readiness_scoped' => {
            'ready': true,
            'suggested_final_award_count': 1,
            'suggested_final_awards': [
              {
                'section_label': 'Open A',
                'species': 'rabbit',
                'award_code': 'BBOS',
                'award_label': bestOppositeAwardLabel,
              },
            ],
          },
          _ => [],
        };
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> pumpAwardSheet(
    WidgetTester tester, {
    String species = 'rabbit',
    String placement = '1',
    String finalAwardMode = bestOppositeFinalAwardMode,
    List<String> awards = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = <String, dynamic>{
      'entry_id': 'entry',
      'species': species,
      'section_id': 'open-a',
      'breed': 'American',
      'variety': 'Black',
      'uses_variety_awards': true,
      'uses_group_awards': false,
      'class_name': 'Senior',
      'sex': species == 'cavy' ? 'Boar' : 'Buck',
      'placement': placement,
      'result_status': 'Shown',
      'is_shown': true,
      '_awards': awards,
      'tattoo': 'VIS-1',
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResultsEntrySheet(
            showId: 'show',
            entry: entry,
            classEntries: [entry],
            judges: const [],
            availablePlacements: const ['1', '2'],
            shownCount: 2,
            currentIndex: 0,
            totalCount: 1,
            breedClassSystems: const {'american': 'four'},
            finalAwardMode: finalAwardMode,
            showsByGroup: false,
            showsByVariety: true,
            isFurOrWoolClass: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder awardTile(String label) =>
      find.widgetWithText(CheckboxListTile, label);

  for (final species in ['rabbit', 'cavy']) {
    testWidgets(
      '$species hides unavailable awards and reveals qualified finals',
      (tester) async {
        await pumpAwardSheet(tester, species: species);
        expect(awardTile('Best of Breed'), findsNothing);
        expect(awardTile('Best Opposite Sex of Breed'), findsNothing);
        expect(awardTile('Best In Show'), findsNothing);
        expect(awardTile(bestOppositeAwardLabel), findsNothing);
        expect(awardTile('Best Junior Variety'), findsNothing);
        expect(awardTile('Best Intermediate Variety'), findsNothing);
        expect(
          awardTile('Best Senior Variety'),
          species == 'cavy' ? findsOneWidget : findsNothing,
        );
        if (species == 'cavy') {
          expect(awardTile('Best Senior of Breed'), findsNothing);
          await tester.tap(awardTile('Best Senior Variety'));
          await tester.pumpAndSettle();
          expect(awardTile('Best Senior of Breed'), findsOneWidget);
        }

        await tester.tap(awardTile('Best of Variety'));
        await tester.pumpAndSettle();
        expect(awardTile('Best Opposite Sex of Variety'), findsNothing);
        expect(awardTile('Best of Breed'), findsOneWidget);
        expect(awardTile('Best Opposite Sex of Breed'), findsOneWidget);
        expect(awardTile('Best In Show'), findsNothing);

        await tester.tap(awardTile('Best of Breed'));
        await tester.pumpAndSettle();
        expect(awardTile('Best Opposite Sex of Breed'), findsNothing);
        expect(awardTile('Best In Show'), findsOneWidget);
        expect(awardTile('1RIS'), findsOneWidget);
        expect(awardTile('Best 4-Class'), findsNothing);
        expect(awardTile('Reserve In Show'), findsNothing);
        expect(awardTile(bestOppositeAwardLabel), findsNothing);

        await tester.tap(awardTile('Best In Show'));
        await tester.pumpAndSettle();
        expect(awardTile('1RIS'), findsNothing);
        expect(awardTile('2RIS'), findsNothing);
        await tester.tap(awardTile('Best In Show'));
        await tester.pumpAndSettle();
        expect(awardTile('1RIS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('four-class rabbit shows only its qualifying class final', (
    tester,
  ) async {
    await pumpAwardSheet(
      tester,
      awards: ['BOV', 'BOB'],
      finalAwardMode: 'four_six_bis',
    );
    expect(awardTile('Best 4-Class'), findsOneWidget);
    expect(awardTile('Best 6-Class'), findsNothing);
    expect(awardTile('Best In Show'), findsNothing);
    await tester.tap(awardTile('Best 4-Class'));
    await tester.pumpAndSettle();
    expect(awardTile('Best In Show'), findsOneWidget);
  });

  testWidgets('stored ineligible awards stay visible and can be removed', (
    tester,
  ) async {
    await pumpAwardSheet(tester, awards: ['BJV', 'Best In Show']);
    for (final label in ['Best Junior Variety', 'Best In Show']) {
      final tile = awardTile(label);
      expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
      expect(tester.widget<CheckboxListTile>(tile).onChanged, isNotNull);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tile, findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-winning entry has no empty awards section', (tester) async {
    await pumpAwardSheet(tester, placement: '2');
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Awards'), findsNothing);
  });

  for (final species in ['rabbit', 'cavy']) {
    for (final qr in [false, true]) {
      testWidgets(
        '$species ${qr ? 'QR' : 'standard'} shows BBOS only after BOS and clears it with BOS',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final entry = <String, dynamic>{
            'entry_id': 'entry',
            'species': species,
            'section_id': 'open-a',
            'breed': 'American',
            'variety': 'Black',
            'uses_variety_awards': true,
            'uses_group_awards': false,
            'class_name': 'Senior',
            'sex': species == 'cavy' ? 'Sow' : 'Doe',
            'placement': '1',
            'result_status': 'Shown',
            'is_shown': true,
            '_awards': ['BOSV'],
            'tattoo': 'BOS-1',
          };
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ResultsEntrySheet(
                  showId: 'show',
                  entry: entry,
                  classEntries: [entry],
                  judges: const [],
                  availablePlacements: const ['1'],
                  shownCount: 1,
                  currentIndex: 0,
                  totalCount: 1,
                  breedClassSystems: const {'american': 'four'},
                  finalAwardMode: bestOppositeFinalAwardMode,
                  showsByGroup: false,
                  showsByVariety: true,
                  isFurOrWoolClass: false,
                  isQrEntryMode: qr,
                  writerName: 'Test Clerk',
                  writerPhone: '5550100',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(bestOppositeAwardLabel), findsNothing);
          final bos = find.widgetWithText(
            CheckboxListTile,
            'Best Opposite Sex of Breed',
          );
          await tester.ensureVisible(bos);
          await tester.tap(bos);
          await tester.pumpAndSettle();
          final opposite = find.widgetWithText(
            CheckboxListTile,
            bestOppositeAwardLabel,
          );
          expect(opposite, findsOneWidget);
          expect(
            tester.widget<CheckboxListTile>(opposite).onChanged,
            isNotNull,
          );
          await tester.ensureVisible(opposite);
          await tester.tap(opposite);
          await tester.pumpAndSettle();
          expect(tester.widget<CheckboxListTile>(opposite).value, isTrue);
          await tester.ensureVisible(bos);
          await tester.tap(bos);
          await tester.pumpAndSettle();
          expect(find.text(bestOppositeAwardLabel), findsNothing);
          await tester.tap(bos);
          await tester.pumpAndSettle();
          expect(tester.widget<CheckboxListTile>(opposite).value, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('closeout shows missing BBOS as an optional warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ShowCloseoutV2PreviewPage(
          showId: 'show',
          showName: 'Synthetic Show',
          canFinalizeShow: true,
        ),
      ),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('closeout-v2-step-2')));
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Missing Best of the Best Opposite'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .join(' | '),
    );
    expect(
      find.textContaining(
        'This is optional and does not block closeout or reports.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Open A • rabbit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
