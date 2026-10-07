import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';

void main() {
  String? reason = 'Breed entry disqualified: Overweight';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode([
            {'entry_id': 'fur', 'blocked_reason': reason},
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entry = <String, dynamic>{
      'entry_id': 'fur',
      'species': 'rabbit',
      'breed': 'Rex',
      'variety': 'Colored',
      'sex': 'Buck',
      'class_name': 'Fur / Wool',
      'tattoo': 'R1',
      'is_fur': true,
      'result_status': 'Shown',
      '_awards': <String>[],
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
            breedClassSystems: const {},
            finalAwardMode: 'bis_ris',
            showsByGroup: false,
            showsByVariety: false,
            isFurOrWoolClass: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('breed DQ explains why fur placement is unavailable', (
    tester,
  ) async {
    await open(tester);
    expect(
      find.textContaining('Fur / Wool unavailable: Breed entry disqualified'),
      findsOneWidget,
    );
    expect(find.text('Placement'), findsNothing);
    expect(find.text('Result Status'), findsOneWidget);
  });
  testWidgets('eligible breed enables fur placement', (tester) async {
    reason = null;
    await open(tester);
    expect(find.text('Placement'), findsOneWidget);
    expect(find.textContaining('Fur / Wool unavailable:'), findsNothing);
  });
}
