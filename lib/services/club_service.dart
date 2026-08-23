// lib/services/club_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_session.dart';

final supabase = Supabase.instance.client;

class ClubService {
  static Future<List<Map<String, dynamic>>> loadMyClubs() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null || userId.isEmpty) return [];

    final rows = await supabase.rpc(
      'get_hosting_clubs_for_user',
      params: {'p_user_id': userId},
    );

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  static bool canManageClubRecord(Map<String, dynamic> club) {
    final role = (club['role'] ?? '').toString().trim().toLowerCase();
    return role == 'owner' || role == 'manager';
  }

  static Future<bool> canSwitchHostingClub() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null || userId.isEmpty) return false;

    return await supabase.rpc(
          'has_active_secretary_license_for_user',
          params: {'p_user_id': userId},
        ) ==
        true;
  }

  static Future<bool> canManageHostingClubs() async {
    final clubs = await loadMyClubs();
    return clubs.isEmpty || clubs.any(canManageClubRecord);
  }

  static Future<Map<String, dynamic>> createClub({required String name}) async {
    if (AppSession.isSupportMode) {
      throw Exception('Club management is unavailable in support mode.');
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in.');
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Club name is required.');
    }

    final createdClub = await supabase
        .from('clubs')
        .insert({'name': trimmed, 'created_by': user.id, 'is_active': true})
        .select('id, name, is_active')
        .single();

    await supabase.from('club_members').insert({
      'club_id': createdClub['id'],
      'user_id': user.id,
      'role': 'owner',
      'is_active': true,
    });

    return Map<String, dynamic>.from(createdClub);
  }

  static Future<void> updateClub({
    required String clubId,
    required String name,
  }) async {
    if (AppSession.isSupportMode) {
      throw Exception('Club management is unavailable in support mode.');
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Club name is required.');
    }

    await supabase.rpc(
      'rename_hosting_club',
      params: {'p_club_id': clubId, 'p_name': trimmed},
    );
  }
}
