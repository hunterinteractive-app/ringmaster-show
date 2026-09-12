// Browser-only app imports require: flutter test --platform chrome
// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';

void main() {
  final reads = <Map<String, dynamic>>[];
  var failBreed = false;
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
        final params = request.body.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        Object response = [];
        if (path == 'show_sections')
          response = [
            {
              'id': 'open',
              'kind': 'open',
              'display_name': 'Open A',
              'is_enabled': true,
            },
            {
              'id': 'youth',
              'kind': 'youth',
              'display_name': 'Youth A',
              'is_enabled': true,
            },
          ];
        if (path == 'shows')
          response = {'final_award_mode': 'bis_ris', 'is_locked': true};
        if (path == 'get_judging_breed_index')
          response = [
            {'breed': 'American', 'breed_key': 'american', 'entry_count': 1},
            {'breed': 'Dutch', 'breed_key': 'dutch', 'entry_count': 1},
          ];
        if (path == 'get_judging_entry_rows_page') {
          reads.add(params);
          if (failBreed && params['p_breed'] != null)
            return http.Response(
              '{"code":"42501","message":"Synthetic read denied"}',
              403,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          response = params['p_after_entry_id'] == null
              ? [
                  for (final breed in ['American', 'Dutch'])
                    if (params['p_breed'] == null || params['p_breed'] == breed)
                      {
                        'entry_id': breed,
                        'section_id': params['p_section_id'],
                        'animal_id': breed,
                        'species': 'rabbit',
                        'breed': breed,
                        'class_name': 'Senior',
                        'sex': 'Buck',
                        'tattoo': breed,
                        'is_shown': false,
                        'result_status': 'No Show',
                        '_awards': <String>[],
                      },
                ]
              : [];
        }
        if (path == 'get_judging_section_readiness') {
          reads.add({'readiness': params});
          response = <String, dynamic>{};
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
    'loads only a selected breed and validates a full section explicitly',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: AdminResultsEntryScreen(
            showId: 'show',
            showName: 'Synthetic Show',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        reads,
        isEmpty,
        reason: 'Landing must not fetch full animal rows or section readiness.',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('American (1 entries)').last);
      await tester.pumpAndSettle();
      expect(reads, isNotEmpty);
      expect(
        reads.every(
          (p) => p['p_breed'] == 'American' && p['p_section_id'] == 'open',
        ),
        isTrue,
      );
      reads.clear();
      await tester.tap(find.byTooltip('Validate full section'));
      await tester.pumpAndSettle();
      expect(
        reads
            .where((p) => p.containsKey('p_breed'))
            .every((p) => p['p_breed'] == null && p['p_section_id'] == 'open'),
        isTrue,
      );
      expect(reads.any((p) => p.containsKey('readiness')), isTrue);
      expect(find.text('Full Section Results Validation'), findsOneWidget);
      Navigator.of(
        tester.element(find.text('Full Section Results Validation')),
      ).pop();
      await tester.pumpAndSettle();
      reads.clear();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Youth A').last);
      await tester.pumpAndSettle();
      expect(
        reads,
        isEmpty,
        reason: 'Changing sections clears the selected breed.',
      );
      failBreed = true;
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dutch (1 entries)').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Load failed:'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
