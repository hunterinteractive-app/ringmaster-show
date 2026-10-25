import 'package:supabase_flutter/supabase_flutter.dart';

class ConventionSaleService {
  static SupabaseClient get _client => Supabase.instance.client;
  static Future<Map<String, dynamic>> settings({bool admin = false}) async =>
      Map<String, dynamic>.from(
        await _client.rpc(
              admin ? 'convention_sale_admin' : 'convention_sale_settings',
            )
            as Map,
      );

  static Future<Map<String, dynamic>> save(
    Map<String, dynamic> settings,
  ) async => Map<String, dynamic>.from(
    await _client.rpc('convention_sale_admin', params: {'p_settings': settings})
        as Map,
  );

  static Future<Map<String, dynamic>> catalog() =>
      _invoke({'action': 'catalog'});

  static Future<Map<String, dynamic>> checkout(
    String plan,
    String requestId,
    Map<String, dynamic> location,
  ) => _invoke({
    'action': 'checkout',
    'plan': plan,
    'request_id': requestId,
    'location_notice_version': '2026-10-25-locality',
    ...location,
  });

  static Future<List<Map<String, dynamic>>> visitors({
    Map<String, dynamic>? before,
  }) async =>
      (await _client.rpc(
                'convention_sale_visitors',
                params: {
                  if (before != null) 'p_before': before['checked_at'],
                  if (before != null) 'p_before_id': before['id'],
                },
              )
              as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

  static Future<Map<String, dynamic>?> purchase(String claimId) async {
    final result = await _client.rpc(
      'convention_sale_purchase',
      params: {'p_claim_id': claimId},
    );
    return result == null ? null : Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(
        'convention-sale-checkout',
        body: body,
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (response.status != 200) {
        throw StateError('${data['error'] ?? 'Unable to open checkout.'}');
      }
      return data;
    } on FunctionException catch (e) {
      final details = e.details;
      throw StateError(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'Checkout is unavailable. Please retry or visit the booth for help.',
      );
    }
  }
}
