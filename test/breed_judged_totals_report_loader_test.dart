import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_judged_totals_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/judge/breed_judged_totals_report_data.dart';
import 'package:ringmaster_show/screens/admin/closeout/pdf/builders/breed_judged_totals_report_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('breed judged totals aggregation', () {
    test('excludes no-shows, scratches, and tests while counting DQs', () {
      final aggregation = aggregateBreedJudgedTotals([
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'result_status': 'placed',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'result_status': 'disqualified',
          'is_disqualified': true,
          'disqualified_reason': 'wrong variety',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'result_status': 'no_show',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'status': 'no show',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'is_shown': false,
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'scratched_at': '2026-07-09T12:00:00Z',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'status': 'scratched',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'is_test': true,
        },
        {
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'result_status': 'placed',
        },
      ]);

      expect(aggregation.breedRows, hasLength(1));
      expect(aggregation.breedRows.single.breed, 'Holland Lop');
      expect(aggregation.breedRows.single.species, 'Rabbit');
      expect(aggregation.breedRows.single.totalJudged, 2);
      expect(aggregation.furRows, isEmpty);
    });

    test('keeps fur/wool counts separate from breed counts', () {
      final aggregation = aggregateBreedJudgedTotals([
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Rex',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Rex',
          'is_fur': true,
          'fur_variety': 'Normal',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Rex',
          'is_fur': true,
          'fur_variety': 'Normal',
        },
      ]);

      expect(aggregation.breedRows.single.totalJudged, 1);
      expect(aggregation.furRows.single.breed, 'Rex');
      expect(aggregation.furRows.single.totalJudged, 2);
    });

    test('sorts cavy breeds alphabetically as separate rows', () {
      final aggregation = aggregateBreedJudgedTotals([
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'cavy',
          'breed': 'American',
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'cavy',
          'breed': 'Abyssinian',
        },
      ]);

      expect(aggregation.breedRows.map((row) => row.breed), [
        'Abyssinian',
        'American',
      ]);
    });

    test('can filter to a show section scope', () {
      final aggregation = aggregateBreedJudgedTotals(
        [
          {
            'judged_by_show_judge_id': 'judge-1',
            'species': 'rabbit',
            'breed': 'Dutch',
            'show_sections': {'kind': 'open', 'letter': 'A'},
          },
          {
            'judged_by_show_judge_id': 'judge-1',
            'species': 'rabbit',
            'breed': 'Dutch',
            'show_sections': {'kind': 'youth', 'letter': 'A'},
          },
        ],
        scope: 'OPEN',
        showLetter: 'A',
      );

      expect(aggregation.breedRows.single.totalJudged, 1);
    });

    test('can filter to selected section ids', () {
      final aggregation = aggregateBreedJudgedTotals(
        [
          {
            'judged_by_show_judge_id': 'judge-1',
            'species': 'rabbit',
            'breed': 'Dutch',
            'section_id': 'section-a',
          },
          {
            'judged_by_show_judge_id': 'judge-1',
            'species': 'rabbit',
            'breed': 'Dutch',
            'section_id': 'section-b',
          },
        ],
        sectionIds: const ['section-a'],
      );

      expect(aggregation.breedRows.single.totalJudged, 1);
    });

    test('can group judged totals by show section', () {
      final breakdowns = aggregateBreedJudgedTotalsByShow([
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Dutch',
          'section_id': 'open-a',
          'show_sections': {
            'id': 'open-a',
            'kind': 'open',
            'letter': 'A',
            'sort_order': 1,
          },
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Rex',
          'section_id': 'open-a',
          'is_fur': true,
          'show_sections': {
            'id': 'open-a',
            'kind': 'open',
            'letter': 'A',
            'sort_order': 1,
          },
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'cavy',
          'breed': 'Abyssinian',
          'section_id': 'youth-a',
          'show_sections': {
            'id': 'youth-a',
            'kind': 'youth',
            'letter': 'A',
            'sort_order': 2,
          },
        },
        {
          'judged_by_show_judge_id': 'judge-1',
          'species': 'rabbit',
          'breed': 'Dutch',
          'section_id': 'open-a',
          'result_status': 'no_show',
          'show_sections': {
            'id': 'open-a',
            'kind': 'open',
            'letter': 'A',
            'sort_order': 1,
          },
        },
      ]);

      expect(breakdowns.map((breakdown) => breakdown.label), [
        'Open Show A',
        'Youth Show A',
      ]);
      expect(breakdowns.first.totalBreedJudged, 1);
      expect(breakdowns.first.totalFurJudged, 1);
      expect(breakdowns.last.totalJudged, 1);
    });
  });

  group('breed judged totals PDF', () {
    test('builds a large report without TooManyPagesException', () async {
      final rows = List<BreedJudgedTotalsReportRow>.generate(
        1500,
        (index) => BreedJudgedTotalsReportRow(
          breed: 'Breed ${index.toString().padLeft(4, '0')}',
          species: index.isEven ? 'Rabbit' : 'Cavy',
          totalJudged: index % 7 + 1,
        ),
      );

      final data = BreedJudgedTotalsReportData(
        show: BreedJudgedTotalsReportShowInfo(
          showId: 'show-1',
          showName: 'Large Test Show',
        ),
        generatedAt: DateTime(2026, 7, 9, 12),
        scopeLabel: 'Entire Show',
        breedRows: rows,
        furRows: const <BreedJudgedTotalsReportRow>[],
        showBreakdowns: [
          BreedJudgedTotalsShowBreakdown(
            label: 'Open Show A',
            breedRows: rows.take(750).toList(),
            furRows: const <BreedJudgedTotalsReportRow>[],
          ),
          BreedJudgedTotalsShowBreakdown(
            label: 'Youth Show A',
            breedRows: rows.skip(750).toList(),
            furRows: const <BreedJudgedTotalsReportRow>[],
          ),
        ],
      );

      final bytes = await BreedJudgedTotalsReportPdfBuilder().build(data);

      expect(bytes, isNotEmpty);
    });
  });
}
