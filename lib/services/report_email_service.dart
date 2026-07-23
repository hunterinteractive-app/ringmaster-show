import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ReportEmailSendResult {
  final bool alreadySent;
  final String providerMessageId;
  final DateTime? sentAt;

  const ReportEmailSendResult({
    required this.alreadySent,
    required this.providerMessageId,
    required this.sentAt,
  });
}

class ReportEmailService {
  Future<ReportEmailSendResult> sendClubReportEmail({
    required String showId,
    required List<String> artifactIds,
    required String to,
    String? subject,
    String? message,
    String? replyTo,
    bool forceResend = false,
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
        'force_resend': forceResend,
      },
    );

    return _validatedSendResult(resp);
  }

  Future<ReportEmailSendResult> sendExhibitorReportEmail({
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

    return _validatedSendResult(resp);
  }

  ReportEmailSendResult _validatedSendResult(FunctionResponse response) {
    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};
    final error = (data['error'] ?? data['message'] ?? '').toString().trim();

    if (response.status < 200 || response.status >= 300) {
      throw Exception(error.isEmpty ? response.data.toString() : error);
    }
    if (data['ok'] != true) {
      throw Exception(
        error.isEmpty ? 'The email provider did not confirm the send.' : error,
      );
    }

    final alreadySent = data['already_sent'] == true;
    final providerMessageId = (data['provider_message_id'] ?? '')
        .toString()
        .trim();
    if (!alreadySent && providerMessageId.isEmpty) {
      throw Exception(
        'The email provider returned success without a message ID.',
      );
    }

    return ReportEmailSendResult(
      alreadySent: alreadySent,
      providerMessageId: providerMessageId,
      sentAt: DateTime.tryParse((data['sent_at'] ?? '').toString()),
    );
  }
}
