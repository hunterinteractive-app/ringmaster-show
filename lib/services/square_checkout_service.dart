import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class SquareCheckoutConfig {
  const SquareCheckoutConfig({
    required this.applicationId,
    required this.locationId,
    required this.environment,
    required this.currency,
  });
  final String applicationId;
  final String locationId;
  final String environment;
  final String currency;
}

class SquarePaymentResult {
  const SquarePaymentResult({
    required this.paymentSessionId,
    required this.finalized,
    required this.pending,
  });
  final String paymentSessionId;
  final bool finalized;
  final bool pending;
}

class SquareCheckoutService {
  SquareCheckoutService._();
  static final _supabase = Supabase.instance.client;

  static Future<SquareCheckoutConfig> loadConfig(String showId) async {
    final data = await _invoke('square-checkout-config', {'show_id': showId});
    return SquareCheckoutConfig(
      applicationId: _required(data, 'application_id'),
      locationId: _required(data, 'location_id'),
      environment: _required(data, 'environment'),
      currency: _required(data, 'currency'),
    );
  }

  static Future<SquarePaymentResult> createPayment({
    required String cartId,
    required String sourceId,
    required String clientAttemptKey,
  }) async {
    final data = await _invoke('square-create-payment', {
      'cart_id': cartId,
      'source_id': sourceId,
      'client_attempt_key': clientAttemptKey,
    });
    return SquarePaymentResult(
      paymentSessionId: _required(data, 'payment_session_id'),
      finalized: data['finalized'] == true,
      pending: data['pending'] == true,
    );
  }

  static Future<bool> isFinalized(String paymentSessionId) async {
    final row = await _supabase
        .from('show_payment_sessions')
        .select('attempt_status')
        .eq('id', paymentSessionId)
        .eq('provider', 'square')
        .maybeSingle();
    return row?['attempt_status'] == 'finalized';
  }

  static Future<Map<String, dynamic>> _invoke(
    String name,
    Map<String, dynamic> body,
  ) async {
    if (_supabase.auth.currentUser == null) {
      throw Exception('Not signed in.');
    }
    final response = await _supabase.functions.invoke(name, body: body);
    final data = _normalize(response.data);
    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        (data['error'] ?? 'Square payment request failed.').toString(),
      );
    }
    return data;
  }

  static String _required(Map<String, dynamic> data, String key) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isEmpty) {
      throw Exception('Square returned an incomplete response.');
    }
    return value;
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
