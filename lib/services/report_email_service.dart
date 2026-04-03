// lib/services/report_email_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ReportEmailService {
  Future<void> sendReportEmail({
    required String showId,
    required String artifactId,
    required String to,
    String? subject,
    String? message,
  }) async {
    final resp = await supabase.functions.invoke(
      'send-report-email',
      body: {
        'show_id': showId,
        'artifact_id': artifactId,
        'to': to,
        'subject': subject,
        'message': message,
      },
    );

    if (resp.status != 200) {
      throw Exception(resp.data.toString());
    }
  }
}