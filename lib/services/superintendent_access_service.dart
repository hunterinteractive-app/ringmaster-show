import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the shows a user may manage from the Superintendent workspace.
///
/// A secretary is a fallback superintendent only when nobody has been given
/// the explicit Superintendent role for that show. This preserves the
/// secretary's ability to prepare a show while keeping the assigned
/// superintendent as the clear owner once one is selected.
class SuperintendentAccessService {
  SuperintendentAccessService._();

  static const _superintendentRole = 'superintendent';
  static const _superAdminRole = 'super_admin';
  static const _secretaryRoles = <String>{
    'admin',
    'show_admin',
    'show_secretary',
    'secretary',
    'show_secretary_admin',
    'show_secretary_full',
  };

  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<bool> hasWorkspaceAccess(String userId) async {
    final access = await loadShowAccess(userId);
    return access.isSuperAdmin || access.showIds.isNotEmpty;
  }

  static Future<SuperintendentShowAccess> loadShowAccess(String userId) async {
    final roleRows = await _supabase
        .from('role_assignments')
        .select('show_id, role')
        .eq('user_id', userId)
        .inFilter('role', <String>[
          _superintendentRole,
          _superAdminRole,
          ..._secretaryRoles,
        ]);

    final assignments = List<Map<String, dynamic>>.from(roleRows as List);
    final isSuperAdmin = assignments.any(
      (row) => _role(row) == _superAdminRole,
    );
    if (isSuperAdmin) {
      return const SuperintendentShowAccess(isSuperAdmin: true);
    }

    final directSuperintendentIds = assignments
        .where((row) => _role(row) == _superintendentRole)
        .map(_showId)
        .where((showId) => showId.isNotEmpty)
        .toSet();

    final fallbackCandidateIds = assignments
        .where((row) => _secretaryRoles.contains(_role(row)))
        .map(_showId)
        .where((showId) => showId.isNotEmpty)
        .toSet();

    // Older shows can still identify their secretary through show_admins or
    // the owning user rather than a role assignment.
    try {
      final legacyAdminRows = await _supabase
          .from('show_admins')
          .select('show_id')
          .eq('user_id', userId);
      fallbackCandidateIds.addAll(
        List<Map<String, dynamic>>.from(
          legacyAdminRows as List,
        ).map(_showId).where((showId) => showId.isNotEmpty),
      );
    } catch (_) {
      // A legacy table or policy must not hide explicitly assigned shows.
    }

    try {
      final ownedShowRows = await _supabase
          .from('shows')
          .select('id')
          .eq('owner_user_id', userId);
      fallbackCandidateIds.addAll(
        List<Map<String, dynamic>>.from(
          ownedShowRows as List,
        ).map(_showId).where((showId) => showId.isNotEmpty),
      );
    } catch (_) {
      // Some legacy shows do not expose owner_user_id to the secretary.
    }

    if (fallbackCandidateIds.isNotEmpty) {
      try {
        final assignedSuperintendentRows = await _supabase
            .from('role_assignments')
            .select('show_id')
            .inFilter('show_id', fallbackCandidateIds.toList())
            .eq('role', _superintendentRole);
        final assignedSuperintendentIds = List<Map<String, dynamic>>.from(
          assignedSuperintendentRows as List,
        ).map(_showId).where((showId) => showId.isNotEmpty).toSet();
        fallbackCandidateIds.removeAll(assignedSuperintendentIds);
      } catch (_) {
        // Do not grant fallback access if the superintendent assignment
        // check cannot be completed.
        fallbackCandidateIds.clear();
      }
    }

    return SuperintendentShowAccess(
      showIds: <String>{...directSuperintendentIds, ...fallbackCandidateIds},
    );
  }

  static String _role(Map<String, dynamic> row) =>
      (row['role'] ?? '').toString().trim();

  static String _showId(Map<String, dynamic> row) =>
      (row['show_id'] ?? row['id'] ?? '').toString().trim();
}

class SuperintendentShowAccess {
  const SuperintendentShowAccess({
    this.isSuperAdmin = false,
    Set<String>? showIds,
  }) : showIds = showIds ?? const <String>{};

  final bool isSuperAdmin;
  final Set<String> showIds;
}
