import 'package:supabase/supabase.dart';

import '../../models/base/report_request.dart';
import '../../models/exhibitor/entered_exhibitors_list_report_data.dart';

class EnteredExhibitorsListReportLoader {
  final SupabaseClient supabase;

  EnteredExhibitorsListReportLoader(this.supabase);

  Future<EnteredExhibitorsListReportData> load(ReportRequest req) async {
    final sectionIds = req.sectionIds ?? const <String>[];
    if (sectionIds.isEmpty) {
      throw StateError('Entered exhibitors list requires scoped section IDs.');
    }

    final rows = await supabase
        .from('entries')
        .select('''
          exhibitor_id,
          exhibitors!entries_exhibitor_id_fkey (
            exhibitor_number,
            display_name,
            first_name,
            last_name
          )
        ''')
        .eq('show_id', req.showId)
        .inFilter('section_id', sectionIds);

    final exhibitors = <String, EnteredExhibitorsListRow>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final exhibitorId = (row['exhibitor_id'] ?? '').toString().trim();
      final exhibitorRaw = row['exhibitors'];
      if (exhibitorId.isEmpty || exhibitorRaw is! Map) continue;

      final exhibitor = Map<String, dynamic>.from(exhibitorRaw);
      exhibitors[exhibitorId] = EnteredExhibitorsListRow(
        exhibitorNumber: (exhibitor['exhibitor_number'] ?? '')
            .toString()
            .trim(),
        lastName: (exhibitor['last_name'] ?? '').toString().trim(),
        firstName: (exhibitor['first_name'] ?? '').toString().trim(),
        displayName: (exhibitor['display_name'] ?? '').toString().trim(),
      );
    }

    final sorted = exhibitors.values.toList()
      ..sort((a, b) {
        final last = a.lastName.toLowerCase().compareTo(
          b.lastName.toLowerCase(),
        );
        if (last != 0) return last;
        final first = a.firstName.toLowerCase().compareTo(
          b.firstName.toLowerCase(),
        );
        if (first != 0) return first;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });

    return EnteredExhibitorsListReportData(
      showId: req.showId,
      showName: req.showName ?? '',
      rows: sorted,
    );
  }
}
