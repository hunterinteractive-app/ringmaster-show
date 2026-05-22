import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ReportEmailService {
  Future<void> sendClubReportEmail({
    required String showId,
    required List<String> artifactIds,
    required String to,
    String? subject,
    String? message,
    String? replyTo,
  }) async {
    final resp = await supabase.functions.invoke(
      'send-report-email',
      body: {
        'show_id': showId,
        'artifact_ids': artifactIds,
        'to': to,
        'subject': subject,
        'message': message,
        'reply_to': replyTo,
      },
    );

    if (resp.status != 200) {
      throw Exception(resp.data.toString());
    }
  }

  Future<void> sendExhibitorReportEmail({
    required String showId,
    required List<String> artifactIds,
    required String to,
    String? subject,
    String? message,
    String? replyTo,
    bool allowLegs = false, // 👈 Leg Change 
  }) async {
    final resp = await supabase.functions.invoke(
      'send-exhibitor-report-email',
      body: {
        'show_id': showId,
        'artifact_ids': artifactIds,
        'to': to,
        'subject': subject,
        'message': message,
        'reply_to': replyTo,
        'allow_legs': allowLegs, 
      },
    );

    if (resp.status != 200) {
      throw Exception(resp.data.toString());
    }
  }
}