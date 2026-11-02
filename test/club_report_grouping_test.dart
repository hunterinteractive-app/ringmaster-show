import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/utils/club_report_grouping.dart';

void main() {
  group('club report picker labels', () {
    test('national Cavy reports do not inherit a state label from format', () {
      expect(
        clubReportPickerLabel(
          reportName: 'details_by_breed',
          title: 'Details By Breed',
          metadata: const [
            {'species': 'cavy', 'sanctioning_body': 'NATIONAL CLUB'},
          ],
        ),
        'Details By Breed (National)',
      );
    });

    test('state breed sweepstakes are labeled state', () {
      expect(
        clubReportPickerLabel(
          reportName: 'sweepstakes_report',
          title: 'Sweepstakes Report',
          metadata: const [
            {'sanctioning_body': 'STATE BREED CLUB'},
          ],
        ),
        'Sweepstakes Report (State)',
      );
    });

    test('shared formats list both audiences once in a stable order', () {
      expect(
        clubReportPickerLabel(
          reportName: 'exh_by_breed',
          title: 'Exhibitors By Breed',
          metadata: const [
            {'sanctioning_body': 'STATE CLUB'},
            {'club_type': 'National Breed Club'},
            {'club_kind': 'state'},
          ],
        ),
        'Exhibitors By Breed (National / State)',
      );
    });

    test('missing sanction metadata does not guess the audience', () {
      expect(
        clubReportPickerLabel(
          reportName: 'sweepstakes_report',
          title: 'Sweepstakes Report',
          metadata: const [{}],
        ),
        'Sweepstakes Report',
      );
    });
  });

  group('emailReportNamesFor', () {
    test('keeps a club report selected when includeReports is true', () {
      expect(
        emailReportNamesFor(
          sourceReportName: 'sweepstakes_report',
          includeReports: true,
          includeLegs: false,
        ),
        {'sweepstakes_report'},
      );
    });

    test('combines exhibitor reports and legs when requested', () {
      expect(
        emailReportNamesFor(
          sourceReportName: 'exhibitor_report',
          includeReports: true,
          includeLegs: true,
        ),
        {'exhibitor_report', 'legs'},
      );
    });
  });

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
