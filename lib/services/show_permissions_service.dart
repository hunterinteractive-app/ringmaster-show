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

  const ShowPermissions({
    required this.canManageShow,
    required this.canEnterResults,
    required this.canManageShowSettings,
    required this.canFinalizeShow,
    required this.canEmailReports,
    required this.canManageEntries,
    required this.canManageJudges,
  });

  static const none = ShowPermissions(
    canManageShow: false,
    canEnterResults: false,
    canManageShowSettings: false,
    canFinalizeShow: false,
    canEmailReports: false,
    canManageEntries: false,
    canManageJudges: false,
  );
}

class ShowPermissionsService {
  ShowPermissionsService._();

  static final _client = Supabase.instance.client;

  static Future<ShowPermissions> load(String showId) async {
    final user = _client.auth.currentUser;
    final effectiveUserId = AppSession.effectiveUserId ?? user?.id;
    if (user == null || effectiveUserId == null || effectiveUserId.isEmpty) {
      return ShowPermissions.none;
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
      canManageShow: results[0],
      canEnterResults: results[1],
      canFinalizeShow: results[2],
      canEmailReports: results[3],
      canManageEntries: results[4],
      canManageJudges: results[5],
      canManageShowSettings: results[6],
    );
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