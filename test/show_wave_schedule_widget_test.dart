// Run with flutter test --platform chrome.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_wave_schedule_dialog.dart';

void main() {
  Map<String, dynamic>? saved;
  var canConfigure = true;
  var completeDates = true;
  var hasEntries = true;
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
        Object? value;
        if (request.url.path.endsWith('get_show_wave_schedule')) {
          value = {
            'enabled': true,
            'timezone': 'America/Chicago',
            'can_configure': canConfigure,
            'waves': [
              {
                'id': 'w1',
                'wave_number': 1,
                'email_lead_hours': 24,
                if (completeDates) ...{
                  'checkin_start_local': '2027-03-10T08:00:00',
                  'checkin_end_local': '2027-03-10T10:00:00',
                  'show_date': '2027-03-11',
                  'checkout_date': '2027-03-12',
                },
              },
            ],
            'breeds': [
              {
                'species': 'rabbit',
                'breed_name': 'Himalayan',
                'wave_id': null,
                'has_entries': hasEntries,
              },
              {
                'species': 'cavy',
                'breed_name': 'American',
                'wave_id': 'w1',
                'has_entries': hasEntries,
              },
              {
                'species': 'rabbit',
                'breed_name': 'Lionhead',
                'wave_id': 'w1',
                'has_entries': false,
              },
            ],
          };
        } else if (request.url.path.endsWith('save_show_wave_schedule')) {
          saved = Map<String, dynamic>.from(jsonDecode(request.body));
        }
        return http.Response(
          jsonEncode(value),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    saved = null;
    canConfigure = true;
    completeDates = true;
    hasEntries = true;
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ShowWaveScheduleDialog.open(
                context,
                showId: 'show',
                showName: 'Houston',
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

  testWidgets(
    'alphabetical breed dropdown and scheduling tabs save selected lead time',
    (tester) async {
      await open(tester);
      expect(find.text('Wave Schedule'), findsOneWidget);
      expect(find.text('Lionhead'), findsNothing);
      expect(
        tester.getTopLeft(find.text('American')).dy,
        lessThan(tester.getTopLeft(find.text('Himalayan')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('rabbit:Himalayan:null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wave 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.textContaining('America/Chicago'), findsOneWidget);
      expect(find.text('Check-in start'), findsOneWidget);
      expect(find.text('Check-in end'), findsOneWidget);
      expect(find.text('Check-out date'), findsOneWidget);
      expect(find.text('24 hours (default)'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 days').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!['p_waves'][0]['email_lead_hours'], 48);
      expect(saved!['p_breeds'][0]['wave_id'], 'w1');
      expect(saved!['p_breeds'][2]['wave_id'], 'w1');
      expect(saved!['p_enabled'], isTrue);
      expect(find.text('Wave Schedule'), findsNothing);
    },
  );
  testWidgets('empty shows and searches explain why there are no breeds', (
    tester,
  ) async {
    hasEntries = false;
    await open(tester);
    expect(
      find.text('No breeds have been entered in this show yet.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.enterText(find.byType(TextField), 'Rex');
    await tester.pumpAndSettle();
    expect(find.text('No entered breeds match your search.'), findsOneWidget);
  });
  testWidgets('incomplete active schedule cannot save', (tester) async {
    completeDates = false;
    await open(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Complete all dates'), findsOneWidget);
    expect(saved, isNull);
  });
  testWidgets('both tabs fit a phone viewport', (tester) async {
    await open(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('unentitled viewer cannot edit or save', (tester) async {
    canConfigure = false;
    await open(tester);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });
}
