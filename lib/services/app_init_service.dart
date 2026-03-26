//lib/services/app_init_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class AppInitService {
  AppInitService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static String? _lastClaimedUserId;
  static bool _claimInProgress = false;

  static Future<void> initializeForCurrentUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (_claimInProgress) return;
    if (_lastClaimedUserId == user.id) return;

    _claimInProgress = true;

    try {
      await _supabase.rpc(
        'claim_pending_licenses',
        params: {
          'p_user_id': user.id,
          'p_email': user.email,
        },
      );

      _lastClaimedUserId = user.id;
      // ignore: avoid_print
      print('Pending licenses checked/applied for ${user.email}');
    } catch (e) {
      // ignore: avoid_print
      print('Error claiming pending licenses: $e');
    } finally {
      _claimInProgress = false;
    }
  }

  static void reset() {
    _lastClaimedUserId = null;
    _claimInProgress = false;
  }
}