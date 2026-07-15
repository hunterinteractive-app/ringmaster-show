import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/closeout/data/loaders/payback_report_loader.dart';

void main() {
  test('large payback show loads in bounded exact-section batches', () async {
    const sectionIds = <String>[
      'open-a',
      'open-b',
      'open-c',
      'youth-a',
      'youth-b',
      'youth-c',
    ];
    const rowsPerSection = 2500;
    final requestedSections = <String>[];
    final timingEvents = <Map<String, Object?>>[];
    var activeRequests = 0;
    var peakActiveRequests = 0;

    final loader = PaybackSectionBatchLoader(
      fetchRows: (showId, sectionId) async {
        expect(showId, 'large-show');
        requestedSections.add(sectionId);
        activeRequests++;
        peakActiveRequests = activeRequests > peakActiveRequests
            ? activeRequests
            : peakActiveRequests;
        await Future<void>.delayed(Duration.zero);
        activeRequests--;
        return List<Map<String, dynamic>>.generate(
          rowsPerSection,
          (index) => <String, dynamic>{
            'entry_id': '$sectionId-entry-$index',
            'section_id': sectionId,
          },
        );
      },
      timingSink: timingEvents.add,
    );

    final rows = await loader.load(
      showId: 'large-show',
      sectionIds: sectionIds,
    );

    expect(requestedSections, sectionIds);
    expect(peakActiveRequests, 1);
    expect(rows, hasLength(sectionIds.length * rowsPerSection));
    expect(timingEvents, hasLength(sectionIds.length));
    for (var index = 0; index < sectionIds.length; index++) {
      expect(timingEvents[index]['event'], 'payback_section_loaded');
      expect(timingEvents[index]['section_id'], sectionIds[index]);
      expect(timingEvents[index]['row_count'], rowsPerSection);
      expect(timingEvents[index]['duration_ms'], isA<int>());
    }
  });
}
