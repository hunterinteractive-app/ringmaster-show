import 'ringmaster_backend.dart';

class EntryDiscountService {
  static Future<List<Map<String, dynamic>>> manage({
    required String showId,
    Map<String, dynamic>? rule,
  }) async {
    final result = await ringMasterClient.rpc(
      'manage_show_discount_code',
      params: {
        'p_show_id': showId,
        if (rule != null) ...{
          'p_action': 'save',
          'p_id': rule['id'],
          'p_code': rule['code'],
          'p_label': rule['label'],
          'p_type': rule['discount_type'],
          'p_basis': rule['basis'],
          'p_value': rule['value'],
          'p_enabled': rule['enabled'],
        },
      },
    );
    return (result as List).map((r) => Map<String, dynamic>.from(r)).toList();
  }

  static Future<Map<String, dynamic>> cart({
    required String cartId,
    String? code,
    String? exhibitorId,
  }) async {
    final result = Map<String, dynamic>.from(
      await ringMasterClient.rpc(
        'entry_cart_discounts',
        params: {
          'p_cart_id': cartId,
          if (code != null) 'p_code': code,
          if (exhibitorId != null) 'p_exhibitor_id': exhibitorId,
        },
      ),
    );
    if (result['error'] != null) throw Exception(result['error']);
    return result;
  }
}
