// lib/services/app_session.dart

import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'support_impersonation_session.dart';
import 'household_session.dart';

class AppSession {
  static SupabaseClient get _supabase => ringMasterClient;

  static String? get effectiveUserId =>
      SupportImpersonationSession.targetUserId ??
      _supabase.auth.currentUser?.id;

  static String? get householdOwnerUserId =>
      supportReadOnly ? impersonatedUserId : HouseholdSession.ownerUserId;

  static String? get impersonatedUserId =>
      SupportImpersonationSession.targetUserId;

  static String? get impersonatedUserEmail =>
      SupportImpersonationSession.current.value?.email;

  static String? get impersonatedUserName =>
      SupportImpersonationSession.current.value?.label;

  static bool get isSupportMode => SupportImpersonationSession.isActive;

  static bool get supportReadOnly => SupportImpersonationSession.readOnly;
  static Future<void> stopImpersonation() =>
      SupportImpersonationSession.finish();
}
