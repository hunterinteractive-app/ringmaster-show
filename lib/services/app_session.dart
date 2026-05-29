// lib/services/app_session.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/super_admin/superadmin_home_screen.dart';

class AppSession {
  static final _supabase = Supabase.instance.client;

  static String? get effectiveUserId =>
      SupportImpersonationSession.targetUserId ??
      _supabase.auth.currentUser?.id;

  static String? get impersonatedUserId =>
      SupportImpersonationSession.targetUserId;

  static String? get impersonatedUserEmail => null;

  static String? get impersonatedUserName => null;

  static bool get isSupportMode =>
      SupportImpersonationSession.isActive;

  static void stopImpersonation() {
    // SupportImpersonationSession does not expose a clear/stop method here yet.
    // Keep this wrapper so shared widgets compile; wire this to the real
    // impersonation exit method once exposed by SupportImpersonationSession.
  }
}