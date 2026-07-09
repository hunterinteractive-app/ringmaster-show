import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/club_report_grouping.dart';

void main() {
  group('club report grouping', () {
    test('normalizes cavy breed club artifacts to one Cavy target', () {
      final metadata = normalizedClubReportMetadata(
        reportName: 'sweepstakes_report',
        metadata: {
          'breed_name': 'Abyssinian',
          'scope': 'OPEN',
          'show_letter': 'A',
          'club_name': 'Cavy Club',
        },
      );

      expect(metadata['species'], 'cavy');
      expect(metadata['breed_name'], cavyClubReportBreedName);
      expect(
        metadata['cavy_club_report_grouping_version'],
        cavyClubReportGroupingVersion,
      );
      expect(
        loaderBreedNameForClubReport(
          reportName: 'sweepstakes_report',
          breedName: metadata['breed_name']?.toString(),
          species: metadata['species']?.toString(),
        ),
        isNull,
      );
    });

    test('keeps rabbit breed club artifacts breed-specific', () {
      final metadata = normalizedClubReportMetadata(
        reportName: 'sweepstakes_report',
        metadata: {
          'breed_name': 'Dutch',
          'species': 'rabbit',
          'scope': 'OPEN',
          'show_letter': 'A',
          'club_name': 'Rabbit Club',
        },
      );

      expect(metadata['species'], 'rabbit');
      expect(metadata['breed_name'], 'Dutch');
      expect(
        loaderBreedNameForClubReport(
          reportName: 'sweepstakes_report',
          breedName: metadata['breed_name']?.toString(),
          species: metadata['species']?.toString(),
        ),
        'Dutch',
      );
    });

    test('uses the same cavy group key for different cavy breeds', () {
      final first = cavyClubReportGroupKey(
        reportName: 'breed_results_detail_report',
        metadata: {
          'breed_name': 'Abyssinian',
          'scope': 'OPEN',
          'show_letter': 'B',
          'club_name': 'Cavy Club',
          'section_id': 'section-1',
        },
      );
      final second = cavyClubReportGroupKey(
        reportName: 'breed_results_detail_report',
        metadata: {
          'breed_name': 'American',
          'scope': 'OPEN',
          'show_letter': 'B',
          'club_name': 'Cavy Club',
          'section_id': 'section-1',
        },
      );

      expect(first, isNotEmpty);
      expect(first, second);
    });
  });
}
