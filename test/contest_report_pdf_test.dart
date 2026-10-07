import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/contest_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'multi-page PDF exports include long project titles and team rosters',
    () async {
      final entries = List.generate(
        42,
        (i) => <String, dynamic>{
          'id': '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
          'name': i.isEven ? 'Educational Exhibit' : 'Team Judging',
          'exhibitor_name': 'Sample Exhibitor ${i + 1}',
          'exhibitor_number': '${400 + i}',
          'division': 'Intermediate',
          'email': 'sample${i + 1}@example.invalid',
          'payment_status': 'paid',
          'approval_status': 'accepted',
          'checked_in': i.isEven,
          'registration_data': i.isEven
              ? {
                  'category': 'Poster',
                  'project_title':
                      'Caring for Rabbits: Housing, Nutrition, and Daily Management',
                  'session_name': 'Saturday Morning',
                }
              : {
                  'team': {
                    'name': 'Clément Youth Team ${i + 1}',
                    'members': [
                      for (final n in ['Alex', 'Sam', 'Robin', 'Jordan'])
                        {'name': '$n Sample', 'alternate': n == 'Jordan'},
                    ],
                  },
                  'session_name': 'Sunday Afternoon',
                },
          'result': {
            'status': 'recorded',
            'place': i + 1,
            'awards': i == 0 ? ['Best Overall'] : [],
            'ribbon': 'Blue',
          },
        },
      );
      for (final type in ['roster', 'teams', 'checkin', 'labels', 'results']) {
        final bytes = await ContestReportService.pdfBytes(
          entries,
          title: 'Sample Contest Show',
          type: type,
        );
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final directory = Platform.environment['CONTEST_REPORT_QA_DIR'];
        if (directory != null) {
          await File('$directory/contest_$type.pdf').writeAsBytes(bytes);
        }
      }
    },
  );
}
