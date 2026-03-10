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

    final row = await supabase
        .from('role_assignments')
        .select('id')
        .eq('user_id', user.id)
        .eq('role', 'super_admin')
        .maybeSingle();

    return row != null;
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
    return roles.any((r) => {
          'super_admin',
          'admin',
          'superintendent',
        }.contains(r));
  }
}