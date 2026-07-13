import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class ShowPaymentProviderOption {
  const ShowPaymentProviderOption({
    required this.provider,
    required this.enabled,
    required this.ready,
  });

  final String provider;
  final bool enabled;
  final bool ready;

  factory ShowPaymentProviderOption.fromJson(Map<String, dynamic> json) {
    return ShowPaymentProviderOption(
      provider: (json['provider'] ?? '').toString().trim().toLowerCase(),
      enabled: json['enabled'] == true,
      ready: json['ready'] == true,
    );
  }
}

class ShowPaymentConfiguration {
  const ShowPaymentConfiguration({
    required this.paymentTimingMode,
    required this.allowOnline,
    required this.allowAtShow,
    required this.requireOnlinePayment,
    required this.defaultOnlineProvider,
    required this.providers,
  });

  final String paymentTimingMode;
  final bool allowOnline;
  final bool allowAtShow;
  final bool requireOnlinePayment;
  final String? defaultOnlineProvider;
  final List<ShowPaymentProviderOption> providers;

  factory ShowPaymentConfiguration.fromJson(Map<String, dynamic> json) {
    final rawProviders = json['providers'];
    final providers = rawProviders is List
        ? rawProviders
              .whereType<Map>()
              .map(
                (provider) => ShowPaymentProviderOption.fromJson(
                  provider.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((provider) => provider.provider.isNotEmpty)
              .toList()
        : <ShowPaymentProviderOption>[];
    final defaultProvider = (json['default_online_provider'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    return ShowPaymentConfiguration(
      paymentTimingMode: (json['payment_timing_mode'] ?? 'pay_at_show_only')
          .toString(),
      allowOnline: json['allow_online'] == true,
      allowAtShow: json['allow_at_show'] == true,
      requireOnlinePayment: json['require_online_payment'] == true,
      defaultOnlineProvider: defaultProvider.isEmpty ? null : defaultProvider,
      providers: providers,
    );
  }
}

class ShowPaymentConfigurationService {
  ShowPaymentConfigurationService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<ShowPaymentConfiguration> load(String showId) async {
    final response = await _supabase.rpc(
      'get_show_checkout_options',
      params: {'p_show_id': showId},
    );

    return ShowPaymentConfiguration.fromJson(_normalizeMap(response));
  }

  static Future<void> save({
    required String showId,
    required String paymentTimingMode,
    required bool stripeEnabled,
    required bool squareEnabled,
    required bool paypalEnabled,
    required String? defaultOnlineProvider,
  }) async {
    await _supabase.rpc(
      'set_show_payment_configuration',
      params: {
        'p_show_id': showId,
        'p_payment_timing_mode': paymentTimingMode,
        'p_stripe_enabled': stripeEnabled,
        'p_square_enabled': squareEnabled,
        'p_paypal_enabled': paypalEnabled,
        'p_default_online_provider': defaultOnlineProvider,
      },
    );
  }

  static Map<String, dynamic> _normalizeMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is List && raw.length == 1 && raw.first is Map) {
      final map = raw.first as Map;
      return map.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }

    throw const FormatException(
      'The checkout configuration response was not valid JSON.',
    );
  }
}
