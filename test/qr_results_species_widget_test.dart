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

void main() {
  final projection = [
    for (var i = 1; i <= 3; i++)
      <String, dynamic>{
        'entry_id': 'entry-$i',
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
        if (path == 'shows') {
          response = {
            'name': 'Synthetic Cavy Show',
            'final_award_mode': 'bis_ris',
            'coop_numbering_mode': 'separate',
          };
        } else if (path == 'show_sections') {
          response = {
            'id': 'open',
            'kind': 'open',
            'display_name': 'Cavy Open A',
            'letter': 'A',
          };
        } else if (path == 'report_results_entry_rows_page') {
          final params = jsonDecode(request.body) as Map;
          response = params['p_after_entry_id'] == null ? projection : [];
        } else if (path == 'entries') {
          expect(request.url.queryParameters['select'], contains('species'));
          response = [
            for (var i = 1; i <= 3; i++)
              {'id': 'entry-$i', 'animal_id': 'animal-$i', 'species': 'cavy'},
          ];
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
        const MaterialApp(
          home: QrResultsEntryScreen(
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
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Synthetic Clerk',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '3175550100');
      await tester.tap(find.text('Continue to Results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('American').last);
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
      expect(tester.takeException(), isNull);
    },
  );
}
