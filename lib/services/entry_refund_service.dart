import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_session.dart';

class EntryRefundService {
  EntryRefundService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<bool> canRefund(String showId) async {
    if (AppSession.isSupportMode) return false;
    return await _client.rpc(
          'can_refund_show_entries',
          params: {'p_show_id': showId},
        ) ==
        true;
  }

  Future<Map<String, dynamic>> options(
    String showId,
    String exhibitorId,
  ) async {
    _assertWritable();
    return Map<String, dynamic>.from(
      await _client.rpc(
        'get_entry_refund_options',
        params: {'p_show_id': showId, 'p_exhibitor_id': exhibitorId},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> history(String showId) async {
    _assertWritable();
    return (await _client.rpc(
              'get_show_entry_refunds',
              params: {'p_show_id': showId},
            )
            as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async {
    _assertWritable();
    try {
      final response = await _client.functions.invoke(
        'refund-show-entries',
        body: body,
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] != null) throw Exception(data['error']);
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      throw Exception(
        details is Map
            ? details['error'] ?? error.reasonPhrase
            : error.reasonPhrase,
      );
    }
  }

  void _assertWritable() {
    if (AppSession.isSupportMode) {
      throw StateError('Exit support mode to manage refunds.');
    }
  }
}

int? refundAmountCents(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

String refundMoney(int cents, String currency) =>
    '${currency.toUpperCase()} ${(cents / 100).toStringAsFixed(2)}';

String refundStatusMessage(String status) => switch (status) {
  'succeeded' => 'Refund completed. Selected entries were removed.',
  'failed' => 'Refund failed. Entries were not removed.',
  'needs_review' =>
    'Refund needs review. Entries are reserved while its status is confirmed.',
  _ => 'Refund is pending. Entries will be removed when the refund succeeds.',
};
