import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentQuotePreview {
  const PaymentQuotePreview({
    required this.provider,
    required this.currency,
    required this.baseTotalCents,
    required this.onlineFeeCents,
    required this.amountDueCents,
    required this.feeLabel,
    required this.feeDescription,
  });

  final String provider;
  final String currency;
  final int baseTotalCents;
  final int onlineFeeCents;
  final int amountDueCents;
  final String feeLabel;
  final String feeDescription;

  static Future<PaymentQuotePreview> load({
    required String cartId,
    required String provider,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'payment-quote-preview',
      body: {'cart_id': cartId, 'provider': provider, 'timing': 'online'},
    );
    final data = _normalize(response.data);
    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        data['error'] ?? 'Unable to calculate online payment total.',
      );
    }
    return PaymentQuotePreview(
      provider: (data['provider'] ?? '').toString(),
      currency: (data['currency'] ?? 'usd').toString(),
      baseTotalCents: (data['base_total_cents'] as num?)?.toInt() ?? 0,
      onlineFeeCents:
          (data['online_processing_fee_cents'] as num?)?.toInt() ?? 0,
      amountDueCents: (data['amount_due_cents'] as num?)?.toInt() ?? 0,
      feeLabel: (data['fee_label'] ?? 'Online Payment Fee').toString(),
      feeDescription: (data['fee_description'] ?? '').toString(),
    );
  }

  static Map<String, dynamic> _normalize(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return <String, dynamic>{};
  }
}
