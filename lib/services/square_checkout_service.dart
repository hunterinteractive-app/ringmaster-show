import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class SquareHostedCheckout {
  const SquareHostedCheckout({
    required this.paymentSessionId,
    required this.checkoutUrl,
  });

  final String paymentSessionId;
  final String checkoutUrl;
}

class SquarePaymentAttemptStatus {
  const SquarePaymentAttemptStatus({
    required this.showId,
    required this.showName,
    required this.status,
    required this.finalized,
    required this.pending,
    required this.terminal,
    this.failureMessage,
    this.applicationFeeTestLimitation,
  });

  final String status;
  final String showId;
  final String showName;
  final bool finalized;
  final bool pending;
  final bool terminal;
  final String? failureMessage;
  final String? applicationFeeTestLimitation;
}

class SquareCheckoutService {
  SquareCheckoutService._();
  static final _supabase = Supabase.instance.client;

  static Future<SquareHostedCheckout> createHostedCheckout({
    required String cartId,
    required String clientAttemptKey,
  }) async {
    final data = await _invoke('square-create-payment', {
      'cart_id': cartId,
      'client_attempt_key': clientAttemptKey,
    });
    if ((data['provider'] ?? '').toString() != 'square') {
      throw Exception('Square returned an invalid checkout response.');
    }
    return SquareHostedCheckout(
      paymentSessionId: _required(data, 'payment_session_id'),
      checkoutUrl: _required(data, 'checkout_url'),
    );
  }

  static Future<SquarePaymentAttemptStatus> loadAttemptStatus({
    required String cartId,
    required String paymentSessionId,
  }) async {
    final data = await _invoke('square-payment-attempt-status', {
      'cart_id': cartId,
      'payment_session_id': paymentSessionId,
    });
    final failure = (data['failure_message'] ?? '').toString().trim();
    final limitation = (data['application_fee_test_limitation'] ?? '')
        .toString()
        .trim();
    return SquarePaymentAttemptStatus(
      showId: _required(data, 'show_id'),
      showName: _required(data, 'show_name'),
      status: _required(data, 'status'),
      finalized: data['finalized'] == true,
      pending: data['pending'] == true,
      terminal: data['terminal'] == true,
      failureMessage: failure.isEmpty ? null : failure,
      applicationFeeTestLimitation: limitation.isEmpty ? null : limitation,
    );
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
        (data['error'] ?? 'Square checkout request failed.').toString(),
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
