import 'package:supabase/supabase.dart';

import '../../models/base/report_request.dart';
import '../../models/other/michelles_special_report_data.dart';

class MichellesSpecialReportLoader {
  MichellesSpecialReportLoader(this.supabase);

  final SupabaseClient supabase;

  Future<MichellesSpecialReportData> load(ReportRequest request) async {
    final rows = await supabase.rpc(
      'michelles_special_report_rows',
      params: {'p_show_id': request.showId},
    );

    return MichellesSpecialReportData(
      showName: request.showName ?? '',
      rows: (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(),
    );
  }
}
