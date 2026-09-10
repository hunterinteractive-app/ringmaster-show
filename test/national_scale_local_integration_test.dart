import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/closeout_repository.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/report_data_reader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/coop_cards_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/entered_exhibitors_list_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/exhibitor_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/legs_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/base/report_request.dart';

const _show = '90000000-0000-0000-0000-000000000001';
const _sections = [
  '91000000-0000-0000-0000-000000000001',
  '91000000-0000-0000-0000-000000000002',
];
String _exhibitor(int n) =>
    '92000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';

ReportRequest _request({int? exhibitor}) => ReportRequest(
  showId: _show,
  reportName: 'Synthetic national loader check',
  finalizeRunId: 'local-read-only',
  sectionIds: _sections,
  exhibitorId: exhibitor == null ? null : _exhibitor(exhibitor),
  species: 'rabbit',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final url = Platform.environment['NATIONAL_TEST_URL'];
  final key = Platform.environment['NATIONAL_TEST_KEY'];
  final enabled = url != null && key != null;
  late SupabaseClient client;
  late CloseoutRepository repo;

  group(
    'national loader lab (repository baseline, service role)',
    () {
      setUpAll(() async {
        final uri = Uri.parse(url!);
        if (uri.scheme != 'http' ||
            !{'127.0.0.1', 'localhost'}.contains(uri.host)) {
          throw StateError('Only a loopback fixture database is allowed.');
        }
        HttpOverrides.global = null;
        client = SupabaseClient(
          url,
          key!,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        );
        repo = CloseoutRepository(client);
        final show = await repo.loadShowBasics(_show);
        expect(show['name'], 'SYNTHETIC National Loader Rehearsal');
        final sanctions = await client
            .from('show_sanctions')
            .select('section_id,sanction_number')
            .eq('show_id', _show)
            .eq('sanctioning_body', 'ARBA');
        expect(
          sanctions.map((row) => row['section_id']).toSet(),
          _sections.toSet(),
        );
        expect(
          sanctions.every(
            (row) => row['sanction_number'].toString().startsWith('SYNTHETIC-'),
          ),
          isTrue,
        );
      });
      tearDownAll(() async => client.dispose());

      test(
        'fixture has 60000 entries, 3000 exhibitors and 30000 coops',
        () async {
          expect(
            await client
                .from('entries')
                .count(CountOption.exact)
                .eq('show_id', _show),
            60000,
          );
          expect(
            await client
                .from('exhibitors')
                .count(CountOption.exact)
                .like('email', 'exhibitor-%@example.test'),
            3000,
          );
          expect(
            await client
                .from('show_animal_coop_numbers')
                .count(CountOption.exact)
                .eq('show_id', _show),
            30000,
          );
          expect(
            await client
                .from('entry_awards')
                .count(CountOption.exact)
                .eq('show_id', _show),
            4,
          );
          expect(
            await client
                .from('animals')
                .count(CountOption.exact)
                .like('tattoo', 'N%'),
            30000,
          );
        },
      );

      test('balance entry loader returns all 60000 unique entry IDs', () async {
        final watch = Stopwatch()..start();
        final rows = await repo.loadEntriesForBalanceReport(_show);
        stdout.writeln(
          'METRIC balance_entries rows=${rows.length} ms=${watch.elapsedMilliseconds}',
        );
        expect(rows.length, 60000);
        expect(rows.map((row) => row['entry_id']).toSet(), hasLength(60000));
      });

      test('entered exhibitor list contains all 3000 exhibitors', () async {
        final watch = Stopwatch()..start();
        final data = await EnteredExhibitorsListReportLoader(
          client,
        ).load(_request());
        stdout.writeln(
          'METRIC entered_exhibitors rows=${data.rows.length} ms=${watch.elapsedMilliseconds}',
        );
        expect(data.rows.length, 3000);
      });

      test('coop loader returns all 30000 animals once', () async {
        final watch = Stopwatch()..start();
        final data = await CoopCardsReportLoader(
          supabase: client,
        ).load(showId: _show);
        stdout.writeln(
          'METRIC coop_cards rows=${data.cards.length} ms=${watch.elapsedMilliseconds}',
        );
        expect(data.cards.length, 30000);
        expect(data.cards.map((row) => row.animalId).toSet(), hasLength(30000));
        expect(data.cards.every((row) => row.showLetters.length == 2), isTrue);
      });

      for (final count in [100, 500]) {
        test('batched ID enrichment returns all $count UUIDs', () async {
          final ids = List.generate(
            count,
            (i) =>
                '94000000-0000-0000-0000-${(i + 1).toString().padLeft(12, '0')}',
          );
          final rows = await loadReportRowsByIds(
            client,
            table: 'entries',
            columns: 'id,animal_id',
            ids: ids,
          );
          stdout.writeln('METRIC id_enrichment_$count rows=${rows.length}');
          expect(rows.length, count);
        });
      }

      for (final exhibitor in [1, 3000]) {
        test(
          'exhibitor $exhibitor receives all 20 entries and correct class counts',
          () async {
            final watch = Stopwatch()..start();
            final data = await ExhibitorReportLoader(
              repo,
            ).load(_request(exhibitor: exhibitor));
            stdout.writeln(
              'METRIC exhibitor_$exhibitor rows=${data.entries.length} '
              'class_counts=${data.entries.map((row) => row.classCount).toSet()} '
              'ms=${watch.elapsedMilliseconds}',
            );
            expect(data.entries.length, 20);
            expect(
              data.entries.every(
                (row) =>
                    row.classCount == (row.breed == 'Mini Rex' ? 24000 : 6000),
              ),
              isTrue,
            );
          },
        );
      }

      test(
        'breed winner receives four legs with complete class counts',
        () async {
          final watch = Stopwatch()..start();
          final rows = await LegsReportLoader(
            repo,
          ).load(_request(exhibitor: 1));
          stdout.writeln(
            'METRIC legs rows=${rows.length} '
            'animal_counts=${rows.map((row) => row.animalsCount).toSet()} '
            'ms=${watch.elapsedMilliseconds}',
          );
          expect(rows.length, 4);
          expect(
            rows.every(
              (row) =>
                  row.animalsCount == (row.breed == 'Mini Rex' ? 24000 : 6000),
            ),
            isTrue,
          );
          expect(rows.every((row) => row.exhibitorsCount == 3000), isTrue);
        },
      );
    },
    skip: enabled
        ? false
        : 'Opt in using tool/national_scale/run.py on the local loader lab.',
  );
}
