// Run with: flutter test --platform chrome test/qr_results_species_widget_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/judging/mobile/qr_results_entry_screen.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  var locked = false;
  var groupedRabbit = false;
  final projection = [
    for (var i = 1; i <= 3; i++)
      <String, dynamic>{
        'entry_id': 'entry-$i',
        'species': 'cavy',
        '_awards': <String>[],
        'section_id': 'open',
        'breed': 'American',
        'variety': 'Black',
        'class_name': 'Senior',
        'uses_variety_awards': true,
        'sex': i == 1
            ? 'Buck'
            : i == 2
            ? 'Boar'
            : 'Doe',
        'tattoo': 'CAVY$i',
        'exhibitor_id': 'exhibitor',
        'is_shown': true,
        'result_status': 'Shown',
        if (i != 2) 'placement': '1',
      },
  ];
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
        Object response = [];
        if (path == 'get_qr_results_context') {
          response = {
            'show': {
              'name': 'Synthetic Cavy Show',
              'final_award_mode': 'bis_ris',
            },
            'section': {
              'kind': 'open',
              'display_name': 'Cavy Open A',
              'letter': 'A',
            },
            'judges': [],
            'breed_class_systems': [],
            'locked': locked,
          };
        } else if (path == 'get_qr_results_entry_rows') {
          final params = jsonDecode(request.body) as Map;
          expect(params['p_section_id'], 'open');
          expect(params['p_breed'], 'American');
          response = params['p_after_entry_id'] != null
              ? []
              : groupedRabbit
              ? [
                  for (final (index, group, variety, awards) in [
                    (0, 'Dark', 'Black', ['BOV', 'BOG']),
                    (2, 'Dark', 'Black', ['BOSV', 'BOSG']),
                    (0, 'Light', 'Blue', ['BOV']),
                  ])
                    {
                      ...projection[index],
                      if (group == 'Light') ...{
                        'entry_id': 'entry-other-group',
                        'tattoo': 'OTHER',
                      },
                      '_awards': awards,
                      'species': 'rabbit',
                      'uses_group_awards': true,
                      'group_name': group,
                      'variety': variety,
                    },
                ]
              : projection;
        } else {
          fail('QR must not query staff reports or private tables: $path');
        }
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

  testWidgets(
    'QR species hydration filters boars and normalizes dialog rows without changing stored labels',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const QrResultsEntryScreen(
            showId: 'show',
            sectionId: 'open',
            breedId: 'American',
            token: 'fixture',
            classSexLabel: 'Senior Boar',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('No matching entries'), findsNothing);
      expect(Supabase.instance.client.auth.currentSession, isNull);
      await tester.tap(find.text('Continue to Results'));
      await tester.pumpAndSettle();
      expect(find.byType(ResultsAnimalsScreen), findsNothing);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Synthetic Clerk',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '3175550100');
      await tester.tap(find.text('Continue to Results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class placements'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Black').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senior Boar').last);
      await tester.pumpAndSettle();
      final screen = tester.widget<ResultsAnimalsScreen>(
        find.byType(ResultsAnimalsScreen),
      );
      expect(screen.entries.map((e) => e['tattoo']), ['CAVY1', 'CAVY2']);
      expect(screen.entries.map((e) => e['species']), ['cavy', 'cavy']);
      expect(screen.entries.map((e) => e['sex']), ['Boar', 'Boar']);
      expect(projection.first['sex'], 'Buck');
      expect(projection.last['sex'], 'Doe');
      await tester.tap(find.textContaining('CAVY1').last);
      await tester.pumpAndSettle();
      expect(find.byType(ResultsEntrySheet), findsOneWidget);
      expect(find.text('Placement'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      projection[1]['placement'] = '2';
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.textContaining('2/2 entered'), findsOneWidget);
      projection.first['_awards'] = ['BOV'];
      final classFooter = find.text('Class awards');
      expect(
        tester.getTopLeft(classFooter).dy,
        greaterThan(tester.getBottomLeft(find.text('Senior Boar')).dy),
      );
      await tester.tap(classFooter);
      await tester.pumpAndSettle();
      expect(find.text('Ear #CAVY1'), findsOneWidget);
      expect(find.text('Ear #CAVY2'), findsNothing);
      expect(find.text('Ear #CAVY3'), findsOneWidget);
      await tester.tap(find.text('Ear #CAVY1'));
      await tester.pumpAndSettle();
      expect(find.text('Record Awards'), findsOneWidget);
      expect(find.text('Placement'), findsNothing);
      expect(find.text('Save & Next'), findsNothing);
      expect(find.byType(CheckboxListTile), findsWidgets);
      expect(
        find.widgetWithText(CheckboxListTile, 'Best of Breed'),
        findsNothing,
      );
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Breed Award'));
      await tester.pumpAndSettle();
      expect(find.text('Ear #CAVY3'), findsNothing);
      expect(find.textContaining('Already awarded: BOV'), findsOneWidget);
      await tester.tap(find.text('Ear #CAVY1'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ResultsEntrySheet),
          matching: find.text('Already awarded: BOV'),
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Best of Breed'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(CheckboxListTile, 'Best of Variety'),
        findsNothing,
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      final awardsSheet = find.byType(ResultsEntrySheet);
      final sheetTheme = Theme.of(tester.element(awardsSheet));
      final foreground = sheetTheme.textTheme.bodyMedium!.color!;
      final background = AppColors.surface;
      final light = background.computeLuminance();
      final dark = foreground.computeLuminance();
      expect((light + .05) / (dark + .05), greaterThanOrEqualTo(4.5));
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Save')).bottom, lessThanOrEqualTo(844));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('grouped rabbit award candidates show the preceding award', (
    tester,
  ) async {
    groupedRabbit = true;
    addTearDown(() => groupedRabbit = false);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const QrResultsEntryScreen(
          showId: 'show',
          sectionId: 'open',
          breedId: 'American',
          token: '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final writerForm = find.text('Continue to Results');
    if (writerForm.evaluate().isNotEmpty) {
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Synthetic Clerk',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '3175550100');
      await tester.tap(writerForm);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Class placements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    final groupFooter = find.text('Class awards');
    expect(
      tester.getTopLeft(groupFooter).dy,
      greaterThan(tester.getBottomLeft(find.text('Black')).dy),
    );
    await tester.tap(groupFooter);
    await tester.pumpAndSettle();
    Finder candidate(String ear) => find.widgetWithText(ListTile, 'Ear #$ear');
    void expectPriorAward(String ear, String award) => expect(
      find.descendant(
        of: candidate(ear),
        matching: find.textContaining('Already awarded: $award'),
      ),
      findsOneWidget,
    );

    expect(candidate('OTHER'), findsNothing);
    expectPriorAward('CAVY1', 'BOV');
    expectPriorAward('CAVY3', 'BOSV');
    await tester.tap(find.text('Ear #CAVY1'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(CheckboxListTile, 'Best of Rabbit Group'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(CheckboxListTile, 'Best of Variety'),
      findsNothing,
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    for (var i = 0; i < 4; i++) {
      navigator.pop();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Breed Award'));
    await tester.pumpAndSettle();
    expectPriorAward('CAVY1', 'BOG');
    expectPriorAward('CAVY3', 'BOSG');
    expect(candidate('OTHER'), findsNothing);
    expect(find.textContaining('Already awarded: BOV'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired QR shows lock instead of writer form', (tester) async {
    locked = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: QrResultsEntryScreen(
          showId: 'show',
          sectionId: 'open',
          breedId: 'American',
          token: '',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This QR results link is locked'),
      findsOneWidget,
    );
    expect(find.text('Continue to Results'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
