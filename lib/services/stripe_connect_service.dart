// lib/services/stripe_connect_service.dart

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class StripeConnectService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Expose client if needed elsewhere
  static SupabaseClient get supabase => _supabase;

  /// Returns the connected Stripe account identifier from a status response.
  ///
  /// Legacy Stripe links store the identifier in `stripe_account_id`, while
  /// provider-neutral links may use `provider_account_id`.
  static String connectedAccountId(Map<String, dynamic>? status) {
    final rawAccount = status?['show_payment_account'];
    if (rawAccount is! Map) return '';

    for (final key in const ['provider_account_id', 'stripe_account_id']) {
      final value = (rawAccount[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  // ============================================================
  // 🚀 MAIN ENTRY POINT (Connect / Continue Setup)
  // ============================================================

  static Future<String> startOnboarding(String showId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    // Reuse the hosting club's saved connection before creating anything.
    await _ensureClubProviderLinks(showId);

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
      body: {'cart_id': cartId},
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

  static Future<Map<String, dynamic>> getAccountStatus(String showId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    await _ensureClubProviderLinks(showId);
    final response = await _supabase.functions.invoke(
      'stripe-connect-account-status',
      body: {'show_id': showId},
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

    await _ensureClubProviderLinks(showId);
    final response = await _supabase.functions.invoke(
      'stripe-connect-account-status',
      body: {'show_id': showId},
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
      body: {'show_id': showId},
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(data, fallback: 'Stripe login link failed.'),
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
      body: {'show_id': showId},
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(data, fallback: 'Stripe account creation failed.'),
      );
    }

    final ok = data['ok'] == true;
    if (!ok) {
      throw Exception(
        _extractBestError(data, fallback: 'Stripe account creation failed.'),
      );
    }

    // A newly connected account belongs to the hosting club.  The show keeps
    // its link for audit history, while later shows inherit the club account.
    await _supabase.rpc(
      'promote_show_payment_provider_link_to_club',
      params: {'p_show_id': showId, 'p_provider': 'stripe'},
    );
  }

  static Future<void> _ensureClubProviderLinks(String showId) async {
    await _supabase.rpc(
      'ensure_show_club_payment_provider_links',
      params: {'p_show_id': showId},
    );
  }

  // ============================================================
  // 🔧 INTERNAL: CREATE ONBOARDING LINK
  // ============================================================

  static Future<String> _createAccountLink({required String showId}) async {
    final response = await _supabase.functions.invoke(
      'stripe-connect-create-account-link-index-ts',
      body: {'show_id': showId},
    );

    final data = _normalizeMap(response.data);

    if (response.status < 200 || response.status >= 300) {
      throw Exception(
        _extractBestError(data, fallback: 'Stripe onboarding link failed.'),
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
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }

    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }

    return <String, dynamic>{};
  }
}
