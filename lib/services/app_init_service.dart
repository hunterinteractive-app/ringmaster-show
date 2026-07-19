//lib/services/app_init_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class AppInitService {
  AppInitService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static String? _lastClaimedUserId;
  static String? _claimingUserId;
  static Future<void>? _claimFuture;

  static Future<void> initializeForCurrentUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (_lastClaimedUserId == user.id) return;

    final inProgress = _claimFuture;
    if (inProgress != null && _claimingUserId == user.id) {
      await inProgress;
      return;
    }

    final claim = _claimPendingLicenses(user);
    _claimingUserId = user.id;
    _claimFuture = claim;

    try {
      await claim;
    } finally {
      if (identical(_claimFuture, claim)) {
        _claimFuture = null;
        _claimingUserId = null;
      }
    }
  }

  static Future<void> _claimPendingLicenses(User user) async {
    try {
      await _supabase.rpc(
        'claim_pending_licenses',
        params: {'p_user_id': user.id, 'p_email': user.email},
      );

      _lastClaimedUserId = user.id;
      // ignore: avoid_print
      print('Pending licenses checked/applied for ${user.email}');
    } catch (e) {
      // ignore: avoid_print
      print('Error claiming pending licenses: $e');
      rethrow;
    }
  }

  static void reset() {
    _lastClaimedUserId = null;
    _claimingUserId = null;
    _claimFuture = null;
  }
}
