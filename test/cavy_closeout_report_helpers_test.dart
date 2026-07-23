import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/breed_results_detail_report_loader.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/legs_report_loader.dart';
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

    test('recognizes fur detail rows from canonical entry fields', () {
      expect(
        breedResultsDetailIsFurOrWoolRow({
          'is_fur': 'true',
          'class_name': 'Senior Doe',
        }),
        isTrue,
      );
      expect(
        breedResultsDetailIsFurOrWoolRow({
          'entry_is_fur': true,
          'class_name': 'Senior Doe',
        }),
        isTrue,
      );
      expect(
        breedResultsDetailIsFurOrWoolRow({
          'entry_fur_variety': 'Colored',
          'class_name': 'Senior Doe',
        }),
        isTrue,
      );
      expect(
        breedResultsDetailIsFurOrWoolRow({
          'is_fur': false,
          'class_name': 'Senior Doe',
        }),
        isFalse,
      );
    });

    test('preserves a normal classification on an optional fur entry', () {
      final regularRow = breedResultsDetailWithoutFurOrWoolFields({
        'is_fur': true,
        'fur_variety': 'White',
        'fur_placement': 1,
        'variety_name': 'White',
        'class_name': 'Senior Buck',
        'placement': 1,
      });

      expect(breedResultsDetailIsFurOrWoolRow(regularRow), isFalse);
      expect(regularRow['variety_name'], 'White');
      expect(regularRow['placement'], 1);
      expect(regularRow['fur_variety'], isEmpty);
      expect(regularRow['fur_placement'], isNull);
    });

    test('recognizes an explicitly dedicated fur result row', () {
      expect(
        breedResultsDetailIsDedicatedFurOrWoolRow({
          'row_type': 'fur',
          'variety_name': 'White',
        }),
        isTrue,
      );
      expect(
        breedResultsDetailIsDedicatedFurOrWoolRow({
          'is_fur': true,
          'fur_variety': 'Colored',
          'variety_name': 'Colored',
        }),
        isFalse,
      );
    });

    test('excludes disqualified entries from judged population counts', () {
      expect(
        breedResultsDetailIsCountableJudgedEntry({
          'result_status': 'Disqualified - Wrong Tattoo',
          'is_shown': true,
        }),
        isFalse,
      );
      expect(
        breedResultsDetailIsCountableJudgedEntry({
          'entry_is_disqualified': true,
          'result_status': 'shown',
        }),
        isFalse,
      );
      expect(
        breedResultsDetailIsCountableJudgedEntry({
          'result_status': 'shown',
          'is_shown': true,
        }),
        isTrue,
      );
    });

    test('uses cavy scoped exhibitor numbers for legs', () {
      expect(
        legExhibitorNumberFromResultRow({
          'species': 'cavy',
          'exhibitor_number': 'C12',
        }, profileExhibitorNumber: '104'),
        'C12',
      );

      expect(
        legExhibitorNumberFromResultRow({
          'species': 'cavy',
        }, profileExhibitorNumber: '104'),
        '',
      );
    });

    test('scopes cavy show-level leg counts to cavy rows', () {
      final cavyWinner = {
        'breed_name': 'Peruvian',
        'sex': 'Boar',
        'entry_id': 'cavy-1',
      };

      expect(
        legShowScopeMatchesResultRow(cavyWinner, {
          'breed_name': 'American Satin',
          'sex': 'Sow',
          'entry_id': 'cavy-2',
        }),
        isTrue,
      );

      expect(
        legShowScopeMatchesResultRow(cavyWinner, {
          'species': 'rabbit',
          'entry_id': 'rabbit-1',
        }),
        isFalse,
      );
    });

    test('infers cavy species for leg counts when result species is blank', () {
      expect(legSpeciesFromResultRow({'sex': 'Boar'}), 'cavy');
      expect(
        legSpeciesFromResultRow({'species': 'rabbit', 'sex': 'Sow'}),
        'cavy',
      );
      expect(legSpeciesFromResultRow({'class_name': 'Senior Sow'}), 'cavy');
      expect(legSpeciesFromResultRow({'breed_name': 'Peruvian'}), 'cavy');
      expect(legSpeciesFromResultRow({'breed_name': 'Rex'}), '');
    });
  });
}
