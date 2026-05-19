// lib/services/stripe_connect_service.dart

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class StripeConnectService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Expose client if needed elsewhere
  static SupabaseClient get supabase => _supabase;

  // ============================================================
  // 🚀 MAIN ENTRY POINT (Connect / Continue Setup)
  // ============================================================

  static Future<String> startOnboarding(String showId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    // Ensure account exists
    await _getOrCreateStripeAccount(showId);

    // Create onboarding link
    final onboardingUrl = await _createAccountLink(showId: showId);

    return onboardingUrl;
  }

  // ============================================================
  // 💳 CHECKOUT SESSION (EXHIBITOR PAYMENT)
  // ============================================================

  static Future<String> createCheckoutSession(String cartId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    final response = await _supabase.functions.invoke(
      'stripe-create-checkout-session',
      body: {
        'cart_id': cartId,
      },
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Stripe checkout session creation failed.',
        ),
      );
    }

    final url = (data['checkout_url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw Exception('Stripe checkout URL was not returned.');
    }

    return url;
  }

  // ============================================================
  // 📊 ACCOUNT STATUS (UI STATE)
  // ============================================================

  static Future<Map<String, dynamic>> getAccountStatus(
    String showId,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    final response = await _supabase.functions.invoke(
      'stripe-connect-account-status',
      body: {
        'show_id': showId,
      },
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Failed to load Stripe account status.',
        ),
      );
    }

    return data;
  }

  static Future<Map<String, dynamic>> refreshAccountStatus(
    String showId,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    final response = await _supabase.functions.invoke(
      'stripe-connect-account-status',
      body: {
        'show_id': showId,
      },
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Failed to refresh Stripe account status.',
        ),
      );
    }

    return data;
  }

  // ============================================================
  // 🔐 LOGIN LINK (STRIPE DASHBOARD ACCESS)
  // ============================================================

  static Future<String> createLoginLink(String showId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    final response = await _supabase.functions.invoke(
      'stripe-connect-create-login-link',
      body: {
        'show_id': showId,
      },
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Stripe login link failed.',
        ),
      );
    }

    final url = (data['url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw Exception('Stripe login URL was not returned.');
    }

    return url;
  }

  // ============================================================
  // 🔧 INTERNAL: CREATE OR REUSE ACCOUNT
  // ============================================================

  static Future<void> _getOrCreateStripeAccount(String showId) async {
    final response = await _supabase.functions.invoke(
      'stripe-connect-create-account-index-ts',
      body: {
        'show_id': showId,
      },
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Stripe account creation failed.',
        ),
      );
    }

    final ok = data['ok'] == true;
    if (!ok) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Stripe account creation failed.',
        ),
      );
    }
  }

  // ============================================================
  // 🔧 INTERNAL: CREATE ONBOARDING LINK
  // ============================================================

  static Future<String> _createAccountLink({
    required String showId,
  }) async {
    final response = await _supabase.functions.invoke(
      'stripe-connect-create-account-link-index-ts',
      body: {
        'show_id': showId,
      },
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(
          data,
          fallback: 'Stripe onboarding link failed.',
        ),
      );
    }

    final url = (data['url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw Exception('Stripe onboarding URL was not returned.');
    }

    return url;
  }

  // ============================================================
  // 🧠 HELPERS
  // ============================================================

  static String _extractBestError(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final error = (data['error'] ?? '').toString().trim();
    if (error.isNotEmpty) return error;

    final details = data['details'];
    if (details is String && details.trim().isNotEmpty) {
      return '$fallback ${details.trim()}';
    }

    return fallback;
  }

  static Map<String, dynamic> _normalizeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }

    return <String, dynamic>{};
  }
}