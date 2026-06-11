// lib/services/show_permissions_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/app_session.dart';

class ShowPermissions {
  final bool canManageShow;
  final bool canEnterResults;
  final bool canFinalizeShow;
  final bool canEmailReports;
  final bool canManageEntries;
  final bool canManageJudges;
  final bool canManageShowSettings;
  final bool isSupportMode;
  final bool isReadOnlySupportMode;

  const ShowPermissions({
    required this.canManageShow,
    required this.canEnterResults,
    required this.canManageShowSettings,
    required this.canFinalizeShow,
    required this.canEmailReports,
    required this.canManageEntries,
    required this.canManageJudges,
    required this.isSupportMode,
    required this.isReadOnlySupportMode,
  });

  static const none = ShowPermissions(
    canManageShow: false,
    canEnterResults: false,
    canManageShowSettings: false,
    canFinalizeShow: false,
    canEmailReports: false,
    canManageEntries: false,
    canManageJudges: false,
    isSupportMode: false,
    isReadOnlySupportMode: false,
  );
}

class ShowPermissionsService {
  ShowPermissionsService._();

  static final _client = Supabase.instance.client;

  static Future<ShowPermissions> load(String showId) async {
    final user = _client.auth.currentUser;
    final effectiveUserId = AppSession.effectiveUserId ?? user?.id;
    final isSupportMode = AppSession.isSupportMode;

    if (user == null || effectiveUserId == null || effectiveUserId.isEmpty) {
      return ShowPermissions.none;
    }

    final isSuperAdmin = await _isSuperAdmin(user.id);

    if (isSuperAdmin && !isSupportMode) {
      return const ShowPermissions(
        canManageShow: true,
        canEnterResults: true,
        canManageShowSettings: true,
        canFinalizeShow: true,
        canEmailReports: true,
        canManageEntries: true,
        canManageJudges: true,
        isSupportMode: false,
        isReadOnlySupportMode: false,
      );
    }

    final results = await Future.wait<bool>([
      _rpcBool('user_can_manage_show', showId, effectiveUserId),
      _rpcBool('user_can_enter_results', showId, effectiveUserId),
      _rpcBool('user_can_finalize_show', showId, effectiveUserId),
      _rpcBool('user_can_email_reports', showId, effectiveUserId),
      _rpcBool('user_can_manage_entries', showId, effectiveUserId),
      _rpcBool('user_can_manage_judges', showId, effectiveUserId),
      _rpcBool('user_can_manage_show_settings', showId, effectiveUserId),
    ]);

    return ShowPermissions(
      canManageShow: isSuperAdmin || results[0],
      canEnterResults: isSuperAdmin || results[1],
      canFinalizeShow: isSuperAdmin || results[2],
      canEmailReports: isSuperAdmin || results[3],
      canManageEntries: isSuperAdmin || results[4],
      canManageJudges: isSuperAdmin || results[5],
      canManageShowSettings: isSuperAdmin || results[6],
      isSupportMode: isSupportMode,
      isReadOnlySupportMode: isSupportMode,
    );
  }

  static Future<bool> _isSuperAdmin(String userId) async {
    try {
      final result = await _client
          .from('role_assignments')
          .select('id')
          .eq('user_id', userId)
          .eq('role', 'super_admin')
          .limit(1);

      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _rpcBool(
    String functionName,
    String showId,
    String effectiveUserId,
  ) async {
    try {
      final result = await _client.rpc(
        functionName,
        params: {
          'p_show_id': showId,
          'p_user_id': effectiveUserId,
        },
      );

      return result == true;
    } catch (_) {
      final result = await _client.rpc(
        functionName,
        params: {'p_show_id': showId},
      );

      return result == true;
    }
  }
}