import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class RoleService {
  static const Set<String> _showAdminRoles = {
    'super_admin',
    'admin',
    'superintendent',
  };

  static const Set<String> _resultsRoles = {
    'super_admin',
    'admin',
    'superintendent',
    'reporting_clerk',
  };

  static Future<bool> isSuperAdmin() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    // Super admins may still be recorded in the original super_admins table,
    // while newer accounts use role_assignments. Recognize both sources.
    try {
      final legacyRow = await supabase
          .from('super_admins')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (legacyRow != null) return true;
    } catch (_) {
      // Continue to the current role source if the legacy table is unavailable.
    }

    try {
      final rows = await supabase
          .from('role_assignments')
          .select('role')
          .eq('user_id', user.id)
          .eq('role', 'super_admin')
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<Set<String>> showRoles(String showId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return <String>{};

    final rows = await supabase
        .from('role_assignments')
        .select('role')
        .eq('show_id', showId)
        .eq('user_id', user.id);

    final set = <String>{};
    for (final r in (rows as List)) {
      final role = (r as Map<String, dynamic>)['role']?.toString();
      if (role != null && role.isNotEmpty) {
        set.add(role);
      }
    }
    return set;
  }

  static Future<String?> primaryShowRole(String showId) async {
    final roles = await showRoles(showId);
    if (roles.isEmpty) return null;

    const priority = [
      'super_admin',
      'admin',
      'superintendent',
      'reporting_clerk',
      'exhibitor',
    ];

    for (final role in priority) {
      if (roles.contains(role)) return role;
    }

    return roles.first;
  }

  static Future<bool> canManageShow(String showId) async {
    final roles = await showRoles(showId);
    return roles.any(_showAdminRoles.contains);
  }

  static Future<bool> canEnterResults(String showId) async {
    final roles = await showRoles(showId);
    return roles.any(_resultsRoles.contains);
  }

  static Future<bool> canAssignJudges(String showId) async {
    final roles = await showRoles(showId);
    return roles.any(
      (r) => {'super_admin', 'admin', 'superintendent'}.contains(r),
    );
  }
}
