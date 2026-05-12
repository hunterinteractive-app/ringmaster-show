// lib/services/app_session.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/super_admin/superadmin_home_screen.dart';

class AppSession {
  static final _supabase = Supabase.instance.client;

  static String? get effectiveUserId =>
      SupportImpersonationSession.targetUserId ??
      _supabase.auth.currentUser?.id;

  static bool get isSupportMode =>
      SupportImpersonationSession.isActive;
}