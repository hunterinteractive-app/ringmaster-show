// lib/screens/admin/closeout/data/loaders/entered_exhibitors_contact_report_loader.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/base/report_request.dart';
import '../../models/exhibitor/entered_exhibitors_contact_report_data.dart';

class EnteredExhibitorsContactReportLoader {
  final SupabaseClient supabase;

  EnteredExhibitorsContactReportLoader(this.supabase);

  Future<EnteredExhibitorsContactReportData> load(ReportRequest req) async {
    final rows = await supabase
        .from('entries')
        .select('''
          exhibitor_id,
          exhibitors!entries_exhibitor_id_fkey (
            id,
            display_name,
            first_name,
            last_name,
            email,
            phone,
            address_line1,
            address_line2,
            city,
            state,
            zip
          )
        ''')
        .eq('show_id', req.showId);

    final Map<String, EnteredExhibitorsContactRow> map = {};

    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final exhibitorId = (row['exhibitor_id'] ?? '').toString().trim();
      final exhibitorRaw = row['exhibitors'];

      if (exhibitorId.isEmpty || exhibitorRaw is! Map) continue;

      final exhibitor = Map<String, dynamic>.from(exhibitorRaw);

      final displayName = (exhibitor['display_name'] ?? '').toString().trim();
      final firstName = (exhibitor['first_name'] ?? '').toString().trim();
      final lastName = (exhibitor['last_name'] ?? '').toString().trim();

      final exhibitorName = displayName.isNotEmpty
          ? displayName
          : [firstName, lastName].where((x) => x.isNotEmpty).join(' ').trim();

      final addressLine1 =
          (exhibitor['address_line1'] ?? '').toString().trim();
      final addressLine2 =
          (exhibitor['address_line2'] ?? '').toString().trim();
      final city = (exhibitor['city'] ?? '').toString().trim();
      final state = (exhibitor['state'] ?? '').toString().trim();
      final zip = (exhibitor['zip'] ?? '').toString().trim();

      String cityStateZip = '';
      if (city.isNotEmpty && state.isNotEmpty && zip.isNotEmpty) {
        cityStateZip = '$city, $state $zip';
      } else if (city.isNotEmpty && state.isNotEmpty) {
        cityStateZip = '$city, $state';
      } else if (city.isNotEmpty && zip.isNotEmpty) {
        cityStateZip = '$city $zip';
      } else if (state.isNotEmpty && zip.isNotEmpty) {
        cityStateZip = '$state $zip';
      } else {
        cityStateZip = [city, state, zip]
            .where((x) => x.isNotEmpty)
            .join(' ')
            .trim();
      }

      final fullAddress = <String>[
        if (addressLine1.isNotEmpty) addressLine1,
        if (addressLine2.isNotEmpty) addressLine2,
        if (cityStateZip.isNotEmpty) cityStateZip,
      ].join('\n');

      map[exhibitorId] = EnteredExhibitorsContactRow(
        exhibitorName: exhibitorName,
        address: fullAddress,
        email: (exhibitor['email'] ?? '').toString().trim(),
        phone: (exhibitor['phone'] ?? '').toString().trim(),
      );
    }

    final sorted = map.values.toList()
      ..sort((a, b) =>
          a.exhibitorName.toLowerCase().compareTo(
                b.exhibitorName.toLowerCase(),
              ));

    return EnteredExhibitorsContactReportData(
      showId: req.showId,
      showName: req.showName ?? '',
      rows: sorted,
    );
  }
}