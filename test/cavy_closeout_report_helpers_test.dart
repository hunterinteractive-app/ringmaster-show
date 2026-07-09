import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/sweepstakes_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/models/clubs/sweepstakes_report_data.dart';

void main() {
  group('cavy closeout report helpers', () {
    test('combines cavy sweepstakes rows by exhibitor', () {
      final combined = combineSweepstakesRowsByExhibitor(const [
        SweepstakesReportRow(
          rank: 1,
          exhibitorName: 'Mary Anne & Al Chmura',
          exhibitorAddress: 'Tivoli, NY',
          classPoints: 6,
          arbaClassPoints: 0,
          varietyPoints: 2,
          groupPoints: 0,
          bobPoints: 5,
          bisPoints: 0,
          furPoints: 0,
          totalPoints: 13,
        ),
        SweepstakesReportRow(
          rank: 1,
          exhibitorName: 'Mary Anne & Al Chmura',
          exhibitorAddress: 'Tivoli, NY',
          classPoints: 4,
          arbaClassPoints: 0,
          varietyPoints: 1,
          groupPoints: 0,
          bobPoints: 3,
          bisPoints: 0,
          furPoints: 0,
          totalPoints: 8,
        ),
        SweepstakesReportRow(
          rank: 1,
          exhibitorName: 'Another Exhibitor',
          exhibitorAddress: 'Albany, NY',
          classPoints: 3,
          arbaClassPoints: 0,
          varietyPoints: 0,
          groupPoints: 0,
          bobPoints: 0,
          bisPoints: 0,
          furPoints: 0,
          totalPoints: 3,
        ),
      ]);

      expect(combined, hasLength(2));
      expect(combined.first.rank, 1);
      expect(combined.first.exhibitorName, 'Mary Anne & Al Chmura');
      expect(combined.first.classPoints, 10);
      expect(combined.first.varietyPoints, 3);
      expect(combined.first.bobPoints, 8);
      expect(combined.first.totalPoints, 21);
      expect(combined.last.rank, 2);
    });

    test('uses breed as top section for combined cavy detail reports', () {
      final row = {'breed_name': 'Abyssinian', 'variety_name': 'Brindle'};

      expect(
        breedResultsDetailTopSectionName(row, groupByBreed: true),
        'Abyssinian',
      );
      expect(
        breedResultsDetailTopSectionName(row, groupByBreed: false),
        'Brindle',
      );
    });

    test('recognizes cavy Boar and Sow sex labels', () {
      expect(
        breedResultsDetailSexLabel({
          'sex': 'Boar',
          'class_name': 'Intermediate',
        }),
        'Boars',
      );
      expect(
        breedResultsDetailSexLabel({'sex': 'Sow', 'class_name': 'Junior'}),
        'Sows',
      );
      expect(normalizeBreedResultsDetailClassName('Senior Boar'), 'Sr Boars');
      expect(normalizeBreedResultsDetailClassName('Junior Sow'), 'Jr Sows');
    });
  });
}
