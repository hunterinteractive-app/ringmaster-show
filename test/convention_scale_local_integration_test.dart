import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/coop_cards_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_contact_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_list_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/legs_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

const _show = '95000000-0000-0000-0000-000000000001';
String _id(String prefix, int n) =>
    '${prefix}00000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
String _section(int n) => _id('951', n);
int _number(Object? id) => int.parse(id.toString().split('-').last);
String _key(Iterable<Object?> fields) => fields.join('|').toUpperCase();

ReportRequest _request({int? exhibitor, int? section}) => ReportRequest(
  showId: _show,
  reportName: 'Synthetic convention loader test',
  finalizeRunId: 'local-read-only',
  sectionIds: section == null
      ? [_section(1), _section(2)]
      : [_section(section)],
  exhibitorId: exhibitor == null ? null : _id('952', exhibitor),
  species: 'rabbit',
);

Future<T> _measure<T>(String label, Future<T> Function() run) async {
  final watch = Stopwatch()..start();
  try {
    return await run();
  } finally {
    stdout.writeln('METRIC $label ms=${watch.elapsedMilliseconds}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Platform.environment['NATIONAL_TEST_URL'];
  final key = Platform.environment['NATIONAL_TEST_KEY'];
  final manifestPath = Platform.environment['CONVENTION_MANIFEST'];
  final enabled = url != null && key != null && manifestPath != null;
  late SupabaseClient client;
  late CloseoutRepository repo;
  late List<Map<String, dynamic>> classes;
  late List<Map<String, dynamic>> breeds;
  late Map<String, dynamic> source;
  final classByEntry = <int, Map<String, dynamic>>{};
  final expectedLegs = <int, (String, int, int)>{};
  final bobEntries = <int>{};

  int exhibitorFor(int n) => n <= 18867
      ? 1 + (n - 1) * 1855 ~/ 18867
      : 1856 + (n - 18868) * 673 ~/ 6844;

  void checkSnapshot(ReportResultSnapshot snapshot, List<int> sections) {
    expect(snapshot.rowsBySection.keys.toSet(), sections.map(_section).toSet());
    for (final section in sections) {
      final kind = section == 1 ? 'open' : 'youth';
      final rows = snapshot.rowsBySection[_section(section)]!;
      expect(rows.length, section == 1 ? 18867 : 6844);
      expect(rows.map((r) => r['entry_id']).toSet(), hasLength(rows.length));
      final breedCounts = <String, int>{};
      final classCounts = <String, int>{};
      for (final row in rows) {
        expect(row['section_id'], _section(section));
        expect(row['section_kind'].toString().toLowerCase(), kind);
        final n = _number(row['entry_id']);
        final c = classByEntry[n]!;
        expect(row['exhibitor_id'], _id('952', exhibitorFor(n)));
        expect(row['animal_id'], _id('953', n));
        expect(row['placement'], n - (c['first'] as int) + 1);
        final breed = row['breed'].toString().toUpperCase();
        breedCounts.update(breed, (v) => v + 1, ifAbsent: () => 1);
        final classKey = _key([
          row['breed'],
          row['group_name'],
          row['variety'],
          row['class_name'],
        ]);
        classCounts.update(classKey, (v) => v + 1, ifAbsent: () => 1);
      }
      // Reconcile breed totals directly against the PDF extraction, separately
      // from the SQL generator's manifest.
      expect(breedCounts, {
        for (final e in (source['breeds'] as Map<String, dynamic>).entries)
          e.key: e.value[kind],
      });
      if (section == 2) {
        expect(classCounts, {
          for (final breed
              in (source['breeds'] as Map<String, dynamic>).entries)
            for (final c in breed.value['youth_classes'] as List)
              _key([breed.key, c[0], c[1], c[2]]): c[3],
        });
      } else {
        expect(classCounts, {
          for (final c in classes.where((c) => c['section'] == 1))
            _key([c['breed'], c['group'], c['variety'], c['class_name']]):
                c['count'],
        });
      }
    }
  }

  group(
    'convention count lab (local baseline, service role)',
    () {
      setUpAll(() async {
        final uri = Uri.parse(url!);
        if (uri.scheme != 'http' ||
            !{'127.0.0.1', 'localhost'}.contains(uri.host)) {
          throw StateError('Only a loopback fixture database is allowed.');
        }
        final manifest =
            jsonDecode(File(manifestPath!).readAsStringSync()) as Map;
        expect(manifest['show_id'], _show);
        expect(manifest['totals'], {
          'open': 18867,
          'youth': 6844,
          'entries': 25711,
          'exhibitors': 2528,
        });
        source = jsonDecode(
          File(
            'tool/national_scale/convention_2024_counts.json',
          ).readAsStringSync(),
        );
        classes = List<Map<String, dynamic>>.from(manifest['classes']);
        breeds = List<Map<String, dynamic>>.from(manifest['breeds']);
        for (final c in classes) {
          for (var n = c['first'] as int; n <= c['last']; n++) {
            expect(classByEntry.containsKey(n), isFalse);
            classByEntry[n] = c;
          }
          if (c['count'] >= 5 && c['exhibitors'] >= 3) {
            expectedLegs[c['first']] = ('FIRST', c['count'], c['exhibitors']);
          }
        }
        for (final b in breeds.where((b) => b['bob'] == true)) {
          bobEntries.add(b['first']);
          if (b['count'] >= 5 && b['exhibitors'] >= 3) {
            expectedLegs[b['first']] = ('BOB', b['count'], b['exhibitors']);
          }
        }
        expect(classByEntry.length, 25711);
        HttpOverrides.global = null;
        client = SupabaseClient(
          url,
          key!,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        repo = CloseoutRepository(client);
        expect(
          (await repo.loadShowBasics(_show))['name'],
          'SYNTHETIC 2024 Convention Counts',
        );
      });
      tearDownAll(() async => client.dispose());

      test('fixture counts and the unchanged 1000-row API cap', () async {
        for (final (table, expected) in [
          ('entries', 25711),
          ('show_animal_coop_numbers', 25711),
          ('entry_awards', 104),
        ]) {
          expect(
            await client
                .from(table)
                .count(CountOption.exact)
                .eq('show_id', _show),
            expected,
          );
        }
        expect(
          await client
              .from('exhibitors')
              .count(CountOption.exact)
              .eq('created_for_show_id', _show),
          2528,
        );
        expect(
          await client
              .from('animals')
              .count(CountOption.exact)
              .like('tattoo', 'C%'),
          25711,
        );
        expect(
          await client.from('entries').select('id').eq('show_id', _show),
          hasLength(1000),
        );
        final sections = await client
            .from('show_sections')
            .select('kind,letter')
            .eq('show_id', _show)
            .order('sort_order', ascending: true);
        expect(sections, [
          {'kind': 'open', 'letter': 'A'},
          {'kind': 'youth', 'letter': 'A'},
        ]);
      });

      test('all breed totals, Youth classes and placements match', () async {
        final snapshot = await _measure(
          'convention_results',
          () => repo.loadResultSnapshot(_show),
        );
        checkSnapshot(snapshot, [1, 2]);
        stdout.writeln(
          'COUNTS results=25711 breed_totals=112 youth_classes=879',
        );
      });

      test('balance entry read contains all 25711 unique IDs', () async {
        final rows = await _measure(
          'convention_balance',
          () => repo.loadEntriesForBalanceReport(_show),
        );
        expect(rows.map((r) => r['entry_id']).toSet(), {
          for (var n = 1; n <= 25711; n++) _id('954', n),
        });
        expect(rows.length, 25711);
      });

      test(
        'exhibitor lists contain all 2528 and isolate Open and Youth',
        () async {
          await _measure(
            'convention_entered_exhibitors_all_and_scoped',
            () async {
              for (final section in [null, 1, 2]) {
                final data = await EnteredExhibitorsListReportLoader(
                  client,
                ).load(_request(section: section));
                final first = section == 2 ? 1856 : 1;
                final last = section == 1 ? 1855 : 2528;
                expect(data.rows.map((r) => r.exhibitorNumber).toSet(), {
                  for (var n = first; n <= last; n++) '$n',
                });
                expect(data.rows.length, last - first + 1);
              }
            },
          );
        },
      );

      for (final scope in [null, 'open', 'youth']) {
        test(
          'coop cards ${scope ?? 'all'} have complete counts and correct scope',
          () async {
            final data = await _measure(
              'convention_coops_${scope ?? 'all'}',
              () => CoopCardsReportLoader(
                supabase: client,
              ).load(showId: _show, scope: scope),
            );
            final first = scope == 'youth' ? 18868 : 1;
            final last = scope == 'open' ? 18867 : 25711;
            expect(data.cards.map((c) => c.animalId).toSet(), {
              for (var n = first; n <= last; n++) _id('953', n),
            });
            expect(data.cards.length, last - first + 1);
            for (final card in data.cards) {
              final n = _number(card.animalId);
              final c = classByEntry[n]!;
              final isOpen = n <= 18867;
              expect(card.scope, isOpen ? 'open' : 'youth');
              expect(card.sectionLabels, [isOpen ? 'Open A' : 'Youth A']);
              expect(card.classEntryCount, c['count'], reason: 'coop $n');
              expect(
                card.classExhibitorCount,
                c['exhibitors'],
                reason: 'coop $n',
              );
            }
          },
        );
      }

      // Boundaries plus owners in the largest breed of each section. The names
      // identify the sample; expected ownership comes from the fixture, not reads.
      for (final sample in [
        'first_open',
        'last_open',
        'first_youth',
        'last_youth',
        'dwarf_open',
        'dwarf_youth',
      ]) {
        test(
          'exhibitor $sample has exact entries, class counts, placements and awards',
          () async {
            final int exhibitor;
            switch (sample) {
              case 'first_open':
                exhibitor = 1;
              case 'last_open':
                exhibitor = 1855;
              case 'first_youth':
                exhibitor = 1856;
              case 'last_youth':
                exhibitor = 2528;
              default:
                final breed = breeds.singleWhere(
                  (b) =>
                      b['breed'] == 'Netherland Dwarf' &&
                      b['section'] == (sample.endsWith('open') ? 1 : 2),
                );
                exhibitor = exhibitorFor(breed['first']);
            }
            final data = await _measure(
              'convention_exhibitor_$sample',
              () => ExhibitorReportLoader(
                repo,
              ).load(_request(exhibitor: exhibitor)),
            );
            final numbers = classByEntry.keys
                .where((n) => exhibitorFor(n) == exhibitor)
                .toSet();
            expect(
              data.entries.map((r) => int.parse(r.tattoo.substring(1))).toSet(),
              numbers,
            );
            expect(data.entries.length, numbers.length);
            for (final row in data.entries) {
              final n = int.parse(row.tattoo.substring(1));
              final c = classByEntry[n]!;
              expect(row.showSection, n <= 18867 ? 'Open A' : 'Youth A');
              expect(row.classCount, c['count'], reason: 'entry $n');
              expect(row.exhibitorCount, c['exhibitors'], reason: 'entry $n');
              expect(row.placing, '${n - (c['first'] as int) + 1}');
              expect(
                row.awardsText,
                bobEntries.contains(n) ? 'Best of Breed' : '',
              );
              expect(row.earnedLeg, expectedLegs.containsKey(n));
            }
          },
        );
      }

      test(
        'all synthetic legs reconcile with class and breed populations',
        () async {
          final rows = await _measure(
            'convention_legs_all',
            () => LegsReportLoader(repo).load(_request()),
          );
          expect(
            rows.map((r) => _number(r.entryId)).toSet(),
            expectedLegs.keys.toSet(),
          );
          expect(rows.length, expectedLegs.length);
          for (final row in rows) {
            final n = _number(row.entryId);
            expect(
              (row.winCode, row.animalsCount, row.exhibitorsCount),
              expectedLegs[n],
              reason: 'leg $n',
            );
            expect(
              row.sanctionNumber,
              n <= 18867 ? 'SYNTHETIC-OPEN' : 'SYNTHETIC-YOUTH',
            );
          }
          stdout.writeln(
            'COUNTS legs=${rows.length} bob=${rows.where((r) => r.winCode == 'BOB').length}',
          );
        },
      );

      test(
        'contact report includes all 2528 exhibitors in the selected sections',
        () async {
          final loader = EnteredExhibitorsContactReportLoader(client);
          for (final scope in [(null, 2528), (1, 1855), (2, 673)]) {
            final data = await _measure(
              'contacts_${scope.$1 ?? 'all'}',
              () => loader.load(_request(section: scope.$1)),
            );
            expect(data.rows.length, scope.$2);
            expect(
              data.rows.map((r) => r.exhibitorName).toSet().length,
              scope.$2,
            );
          }
        },
      );

      test('four concurrent report reads remain complete', () async {
        await _measure('convention_four_concurrent_reads', () async {
          await Future.wait([
            for (final s in [1, 2])
              repo
                  .loadResultSnapshot(_show, sectionIds: [_section(s)])
                  .then((snapshot) => checkSnapshot(snapshot, [s])),
            repo.loadEntriesForBalanceReport(_show).then((rows) {
              expect(rows.length, 25711);
              expect(rows.map((r) => r['entry_id']).toSet(), hasLength(25711));
            }),
            EnteredExhibitorsListReportLoader(client).load(_request()).then((
              data,
            ) {
              expect(data.rows.length, 2528);
              expect(
                data.rows.map((r) => r.exhibitorNumber).toSet(),
                hasLength(2528),
              );
            }),
          ]);
        });
      });
    },
    skip: enabled
        ? false
        : 'Opt in using the convention scenario in tool/national_scale/run.py.',
  );
}
