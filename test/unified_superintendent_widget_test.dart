import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/superintendent/superintendent_lineup_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final mutations = <Map<String, dynamic>>[];
  var withSpecialty = false;
  var judgeCount = 1;
  var withAwards = false;
  var specialtyHasJudge = true;
  var specialtyCount = 45;
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
        Object? result = [];
        final path = request.url.path;
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        final show =
            body['p_show_id'] ??
            request.url.queryParameters['show_id']?.substring(3);
        final names = show == 'sala'
            ? ['Open A', 'Open B', 'Youth A', 'Youth B']
            : ['Open A', 'Youth A'];
        if (path.endsWith('/ensure_show_lineup_workspace')) result = 'shared';
        if (path.endsWith('/superintendent_workspaces')) {
          result = {'id': 'shared'};
        }
        if (path.endsWith('/shows')) {
          result = {'superintendent_judge_order_published': false};
        }
        if (path.endsWith('/show_sections')) {
          result = [
            for (final name in names)
              {
                'id': '$show-$name',
                'display_name': name,
                'kind': name.startsWith('Open') ? 'open' : 'youth',
                'letter': name.split(' ').last,
              },
          ];
        }
        if (path.endsWith('/show_sections') &&
            request.url.queryParameters['show_id']?.startsWith('in.') == true) {
          result = withAwards
              ? [
                  for (final source in ['sala', 'dune'])
                    for (final kind in ['open', 'youth'])
                      {
                        'id': '$source-$kind-A',
                        'show_id': source,
                        'kind': kind,
                        'letter': 'A',
                        'is_enabled': true,
                        'shows': {
                          'final_award_mode': source == 'sala'
                              ? 'four_six_bis'
                              : 'bis_1ris_2ris',
                        },
                      },
                ]
              : [];
        }
        if ((withAwards || (withSpecialty && specialtyHasJudge)) &&
            path.endsWith('/get_show_judging_lineup') &&
            show == 'sala') {
          result = [
            {
              'id': 'marker',
              'show_id': 'sala',
              'breed_id': '__judge_change__',
              'is_judge_change': true,
              'judge_id': 'judge1',
              'judge_name': 'Shared Judge',
              'table_number': '1',
              'sort_order': 0,
            },
          ];
        }
        if (path.endsWith('/get_show_lineup_breed_counts')) {
          result = [
            for (final name in names)
              {
                'show_id': show,
                'section_id': '$show-$name',
                'show_letter': name.split(' ').last,
                'section_label': name,
                'breed': 'Havana',
                'species': 'rabbit',
                'entry_count': 2,
              },
          ];
        }
        if (path.endsWith('/get_show_lineup_judges')) {
          result = [
            for (var j = 1; j <= judgeCount; j++)
              {
                'judge_id': 'judge$j',
                'judge_name': 'Shared Judge $j',
                'is_enabled': true,
              },
          ];
        }
        if (path.endsWith('/workspace_specialties') && withSpecialty) {
          result = [
            {
              'id': 'specialty',
              'name': 'IDDRC',
              'breed': 'Dutch',
              'entry_count': specialtyCount,
              'table_number': '1',
              'sort_order': 1,
              'judge_name': 'Guest Judge',
              'status': 'draft',
            },
          ];
        }
        if (path.endsWith('/mutate_workspace_lineup')) mutations.add(body);
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  Future<void> open(WidgetTester tester, {bool single = false}) async {
    mutations.clear();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: SuperintendentLineupScreen(
          showId: 'sala',
          showName: 'Both shows',
          workspaceId: single ? null : 'shared',
          linkedShows: single ? const {} : {'sala': 'Sala', 'dune': 'Dune'},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'specialty counts toward assigned judge workload and planning totals',
    (tester) async {
      withSpecialty = true;
      addTearDown(() => withSpecialty = false);
      await open(tester);
      expect(find.text('45/57'), findsOneWidget);
      expect(
        find.textContaining('Includes 45 outside specialty entries'),
        findsOneWidget,
      );
      expect(find.textContaining('Judge moved'), findsNothing);
      expect(find.text('45'), findsWidgets);
      expect(find.textContaining('IDDRC • Dutch'), findsOneWidget);
      expect(find.textContaining('Guest Judge'), findsNothing);
      await tester.tap(find.text('Specialty'));
      await tester.pumpAndSettle();
      expect(find.text('Outside specialties'), findsOneWidget);
      expect(find.textContaining('45 entries'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('specialty without a judge stays unassigned', (tester) async {
    withSpecialty = true;
    specialtyHasJudge = false;
    addTearDown(() {
      withSpecialty = false;
      specialtyHasJudge = true;
    });
    await open(tester);
    expect(find.text('0/57'), findsOneWidget);
    expect(find.text('Table has breeds — fill with judge.'), findsOneWidget);
    expect(find.textContaining('Judge moved'), findsNothing);
  });

  testWidgets('zero-head assignment does not imply judge moved', (
    tester,
  ) async {
    withSpecialty = true;
    specialtyCount = 0;
    addTearDown(() {
      withSpecialty = false;
      specialtyCount = 45;
    });
    await open(tester);
    expect(find.text('0/12'), findsOneWidget);
    expect(find.textContaining('Judge moved'), findsNothing);
    expect(find.text('Table has breeds — fill with judge.'), findsNothing);
  });

  testWidgets('single club show exposes Specialty after Auto Fill', (
    tester,
  ) async {
    await open(tester, single: true);
    final auto = find.text('Auto Fill');
    final specialty = find.text('Specialty');
    expect(specialty, findsOneWidget);
    expect(
      tester.getCenter(specialty).dx,
      greaterThan(tester.getCenter(auto).dx),
    );
    await tester.tap(specialty);
    await tester.pumpAndSettle();
    expect(find.text('Outside specialties'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'one table pool and Auto Fill includes all six separate sections',
    (tester) async {
      await open(tester);
      expect(find.text('Table 1'), findsOneWidget);
      expect(find.text('Table 2'), findsNothing);
      expect(find.text('0/12'), findsOneWidget);
      await tester.tap(find.text('Auto Fill').first);
      await tester.pumpAndSettle();
      final replacement = mutations.singleWhere(
        (m) => m['p_action'] == 'replace',
      );
      final rows = List<Map<String, dynamic>>.from(
        replacement['p_payload']['rows'],
      );
      expect(rows.where((r) => r['p_is_judge_change'] == true).length, 1);
      expect(
        rows
            .where((r) => r['p_section_id'] != null)
            .map((r) => r['p_section_id'])
            .toSet(),
        {
          'sala-Open A',
          'sala-Open B',
          'sala-Youth A',
          'sala-Youth B',
          'dune-Open A',
          'dune-Youth A',
        },
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Auto Fill pairs Youth then Open and puts linked C last', (
    tester,
  ) async {
    judgeCount = 3;
    addTearDown(() => judgeCount = 1);
    await open(tester);
    await tester.tap(find.text('Auto Fill').first);
    await tester.pumpAndSettle();
    final replacement = mutations.singleWhere(
      (m) => m['p_action'] == 'replace',
    );
    final rows = List<Map<String, dynamic>>.from(
      replacement['p_payload']['rows'],
    ).where((r) => r['p_section_id'] != null).toList();
    expect(rows.map((r) => r['p_section_id']).toList(), [
      'sala-Youth A',
      'sala-Open A',
      'sala-Youth B',
      'sala-Open B',
      'dune-Youth A',
      'dune-Open A',
    ]);
    for (var i = 0; i < rows.length; i += 2) {
      expect(rows[i]['p_table_number'], rows[i + 1]['p_table_number']);
      expect(rows[i + 1]['p_sort_order'], rows[i]['p_sort_order'] + 1);
    }
    expect(rows.map((r) => r['p_table_number']).toSet().length, 3);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Breed picker adds one private combined finals plan without counts',
    (tester) async {
      withAwards = true;
      addTearDown(() => withAwards = false);
      await open(tester);
      await tester.tap(find.text('Breed').first);
      await tester.pumpAndSettle();
      final award = find.text('C · Dune • Open • BIS / RIS / 2RIS');
      await tester.scrollUntilVisible(
        award,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(award, findsOneWidget);
      final tile = find.ancestor(of: award, matching: find.byType(ListTile));
      expect(
        find.descendant(of: tile, matching: find.text('0 entered')),
        findsNothing,
      );
      await tester.tap(award);
      await tester.pumpAndSettle();
      final call = mutations.singleWhere((m) => m['p_action'] == 'award_add');
      expect(call['p_payload']['p_award_code'], 'FINALS');
      expect(call['p_payload']['p_section_id'], 'dune-open-A');
      expect(call['p_payload'].containsKey('p_entry_count_actual'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('one shared sync and one publishing control', (tester) async {
    await open(tester);
    await tester.tap(find.text('Sync Judges'));
    await tester.pumpAndSettle();
    expect(mutations.single['p_action'], 'sync');
    expect(mutations.single['p_workspace_id'], 'shared');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // Empty lineup needs confirmation before publishing.
    final publish = find.text('Publish anyway');
    if (publish.evaluate().isNotEmpty) {
      await tester.tap(publish);
      await tester.pumpAndSettle();
    }
    expect(mutations.where((m) => m['p_action'] == 'publish').length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'breed picker lists matching letters from both shows separately',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Breed').first);
      await tester.pumpAndSettle();
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(text, contains('Sala'));
      expect(text, contains('Dune'));
      expect(tester.takeException(), isNull);
    },
  );
}
