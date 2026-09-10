import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/legs_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

void main() {
  test(
    'exhibitor counts preserve DQ rules and separate Open A from Youth A',
    () async {
      final fixture = _Fixture(_qualificationRows());
      addTearDown(fixture.client.dispose);
      final data = await ExhibitorReportLoader(fixture.repo).load(_request);
      final byTattoo = {for (final row in data.entries) row.tattoo: row};
      expect(byTattoo['a']!.classCount, 5);
      expect(byTattoo['a']!.exhibitorCount, 5);
      expect(byTattoo['a']!.earnedLeg, isTrue);
      expect(byTattoo['y']!.classCount, 2);
      expect(byTattoo['y']!.earnedLeg, isFalse);
      expect(
        fixture.repo.snapshotLoads,
        1,
        reason: 'The leg check reuses this report snapshot.',
      );
    },
  );

  for (final (award, animals) in [
    ('FIRST', 5),
    ('BOB', 8),
    ('BOG', 7),
    ('BOV', 7),
    ('BIS', 9),
  ]) {
    test(
      '$award preserves its own eligibility population ($animals)',
      () async {
        final fixture = _Fixture(_qualificationRows(), award: award);
        addTearDown(fixture.client.dispose);
        final legs = await LegsReportLoader(fixture.repo).load(_request);
        expect(legs.length, 1);
        expect(legs.single.entryId, 'a');
        expect(legs.single.winCode, award);
        expect(legs.single.animalsCount, animals);
        expect(legs.single.exhibitorsCount, animals);
      },
    );
  }

  test(
    'BIS populations keep rabbits and cavies separate in the same section',
    () async {
      final rows = <Map<String, dynamic>>[
        for (var i = 0; i < 5; i++)
          _row(i == 0 ? 'a' : 'r$i', exhibitor: 'ex${i + 1}'),
        for (var i = 0; i < 7; i++)
          _row(
            'c$i',
            exhibitor: 'cavy$i',
            values: {
              'species': 'cavy',
              'sex': 'Boar',
              'breed_name': 'American',
            },
          ),
      ];
      final fixture = _Fixture(rows, award: 'BIS');
      addTearDown(fixture.client.dispose);
      final legs = await LegsReportLoader(fixture.repo).load(_request);
      expect(legs.single.animalsCount, 5);
      expect(legs.single.exhibitorsCount, 5);
    },
  );

  test(
    'a later report reads changed results instead of reusing a stale snapshot',
    () async {
      final rows = _qualificationRows();
      final fixture = _Fixture(rows);
      addTearDown(fixture.client.dispose);
      final loader = ExhibitorReportLoader(fixture.repo);
      final first = await loader.load(_request);
      expect(
        first.entries.firstWhere((row) => row.tattoo == 'a').classCount,
        5,
      );
      rows.removeWhere((row) => row['entry_id'] == 'b');
      final next = await loader.load(_request);
      expect(next.entries.firstWhere((row) => row.tattoo == 'a').classCount, 4);
      expect(fixture.repo.snapshotLoads, 2);
    },
  );

  test('failed points read cannot produce a report with zero points', () async {
    final fixture = _Fixture(_qualificationRows(), failPoints: true);
    addTearDown(fixture.client.dispose);
    await expectLater(
      ExhibitorReportLoader(fixture.repo).load(_request),
      throwsA(isA<PostgrestException>()),
    );
  });

  test(
    'failed award reads fail the report instead of reporting no awards',
    () async {
      final fixture = _Fixture(_qualificationRows(), failAwards: true);
      addTearDown(fixture.client.dispose);
      await expectLater(
        ExhibitorReportLoader(fixture.repo).load(_request),
        throwsA(isA<PostgrestException>()),
      );
    },
  );
}

final _request = ReportRequest(
  showId: 'show',
  reportName: 'regression',
  finalizeRunId: 'run',
  sectionIds: ['open', 'youth'],
  exhibitorId: 'ex1',
  species: 'rabbit',
);

Map<String, dynamic> _row(
  String id, {
  String exhibitor = 'ex1',
  String section = 'open',
  Map<String, dynamic> values = const {},
}) => {
  'entry_id': id,
  'section_id': section,
  'exhibitor_id': exhibitor,
  'species': 'rabbit',
  'breed_name': 'Mini Rex',
  'variety_name': 'Black',
  'group_name': 'Self',
  'uses_group_awards': true,
  'sex': 'Buck',
  'class_name': 'Senior Buck',
  'tattoo': id,
  'is_shown': true,
  'placement': id == 'a' || id == 'y' ? 1 : 2,
  'judged_by_show_judge_id': 'judge',
  'exhibitor_number': exhibitor,
  'exhibitor_display_name': exhibitor,
  'exhibitor_city': 'Localtown',
  ...values,
};

List<Map<String, dynamic>> _qualificationRows() => [
  _row('a'), _row('b', exhibitor: 'ex2'), _row('c', exhibitor: 'ex3'),
  _row(
    'no-show',
    exhibitor: 'ex4',
    values: {'is_shown': false, 'result_status': 'No Show'},
  ),
  _row(
    'wrong-sex',
    exhibitor: 'ex5',
    values: {'is_disqualified': true, 'disqualified_reason': 'Wrong Sex'},
  ),
  _row(
    'other',
    exhibitor: 'ex6',
    values: {'is_disqualified': true, 'disqualified_reason': 'Other'},
  ),
  _row(
    'overweight',
    exhibitor: 'ex7',
    values: {'is_disqualified': true, 'disqualified_reason': 'Overweight'},
  ),
  _row(
    'wrong-class',
    exhibitor: 'ex8',
    values: {'is_disqualified': true, 'disqualified_reason': 'Wrong Class'},
  ),
  _row(
    'wrong-variety',
    exhibitor: 'ex9',
    values: {'is_disqualified': true, 'disqualified_reason': 'Wrong Variety'},
  ),
  _row(
    'unworthy',
    exhibitor: 'ex10',
    values: {'result_status': 'Unworthy of Award'},
  ),
  _row('scratch', exhibitor: 'ex11', values: {'scratched_at': '2026-09-10'}),
  // Duplicate fur result for the same entry must not inflate its population.
  _row(
    'other',
    exhibitor: 'ex6',
    values: {
      'is_fur': true,
      'is_disqualified': true,
      'disqualified_reason': 'Other',
    },
  ),
  _row('y', section: 'youth'), _row('y2', section: 'youth', exhibitor: 'ex2'),
];

class _Fixture {
  _Fixture(
    List<Map<String, dynamic>> rows, {
    String award = 'FIRST',
    bool failAwards = false,
    bool failPoints = false,
  }) {
    client = SupabaseClient(
      'http://fixture.invalid',
      'fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        if ((table == 'entry_awards' && failAwards) ||
            (table == 'sweepstakes_entry_results' && failPoints)) {
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'read failed'}),
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        Object data = <Object>[];
        if (table == 'shows') {
          final show = {
            'id': 'show',
            'name': 'Fixture',
            'start_date': '2026-09-10',
          };
          data = request.headers['Accept']?.contains('object') == true
              ? show
              : [show];
        } else if (table == 'show_sanctions') {
          data = [
            for (final section in ['open', 'youth'])
              {'section_id': section, 'sanction_number': 'SYN-$section'},
          ];
        } else if (table == 'entry_awards' && award != 'FIRST') {
          data = [
            {
              'id': 'award',
              'show_id': 'show',
              'entry_id': 'a',
              'award_code': award,
              'entries': {
                'id': 'a',
                'show_id': 'show',
                'exhibitor_id': 'ex1',
                'species': 'rabbit',
                'breed': 'Mini Rex',
                'tattoo': 'a',
                'sex': 'Buck',
                'class_name': 'Senior Buck',
                'is_shown': true,
              },
            },
          ];
        } else if (table == 'judges') {
          data = [
            {'id': 'judge', 'name': 'Synthetic Judge'},
          ];
        }
        if (data is List) {
          final offset =
              int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
          final limit =
              int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 1000;
          data = data.skip(offset).take(limit).toList();
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    repo = _FixtureRepository(client, rows);
  }
  late final SupabaseClient client;
  late final _FixtureRepository repo;
}

class _FixtureRepository extends CloseoutRepository {
  _FixtureRepository(super.client, this.rows);
  final List<Map<String, dynamic>> rows;
  int snapshotLoads = 0;
  @override
  Future<ReportResultSnapshot> loadResultSnapshot(
    String showId, {
    List<String>? sectionIds,
  }) async {
    snapshotLoads++;
    final sections = ['open', 'youth'].where(
      (id) =>
          sectionIds == null || sectionIds.isEmpty || sectionIds.contains(id),
    );
    return ReportResultSnapshot(
      showId: showId,
      sections: [
        for (final id in sections)
          {
            'id': id,
            'kind': id,
            'letter': 'A',
            'sort_order': id == 'open' ? 1 : 2,
          },
      ],
      rowsBySection: {
        for (final id in sections)
          id: rows
              .where((row) => row['section_id'] == id)
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
      },
    );
  }
}
