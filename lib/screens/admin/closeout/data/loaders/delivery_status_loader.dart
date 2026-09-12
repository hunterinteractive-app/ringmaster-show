import 'package:supabase/supabase.dart';

import '../report_data_reader.dart';

class DeliveryStatusData {
  const DeliveryStatusData(this.deliveries, this.artifacts, this.exhibitors);
  final ReportRows deliveries;
  final ReportRows artifacts;
  final ReportRows exhibitors;
}

Future<DeliveryStatusData> loadDeliveryStatus(
  SupabaseClient client,
  String showId,
) async {
  final deliveries = await readAllReportPages(
    (from, to) => client
        .from('show_email_deliveries')
        .select(
          'id,artifact_id,recipient_name,recipient_email,report_name,'
          'delivery_status,error_message,provider_message_id,subject,sent_at,created_at',
        )
        .eq('show_id', showId)
        .order('created_at', ascending: false)
        .order('id')
        .range(from, to),
  );
  // Include superseded artifacts: an older delivery still refers to its file.
  final artifacts = await readAllReportPages(
    (from, to) => client
        .from('show_report_artifacts')
        .select('id,file_name,metadata')
        .eq('show_id', showId)
        .order('id')
        .range(from, to),
  );
  final exhibitors = await loadReportRowsByIds(
    client,
    table: 'exhibitors',
    columns: 'id,email,display_name,first_name,last_name',
    ids: artifacts.map(
      (artifact) =>
          ((artifact['metadata'] as Map?)?['exhibitor_id'] ?? '').toString(),
    ),
  );
  return DeliveryStatusData(deliveries, artifacts, exhibitors);
}
