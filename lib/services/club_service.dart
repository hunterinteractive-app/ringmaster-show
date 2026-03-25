import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ClubService {
  static Future<List<Map<String, dynamic>>> loadMyClubs() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final rows = await supabase
        .from('club_members')
        .select('club_id, role, clubs!club_members_club_id_fkey(id, name, is_active)')
        .eq('user_id', user.id)
        .eq('is_active', true);

    final list = <Map<String, dynamic>>[];

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final club = row['clubs'];
      if (club is Map<String, dynamic>) {
        if (club['is_active'] == true) {
          list.add({
            'id': club['id'],
            'name': club['name'],
            'role': row['role'],
          });
        }
      } else if (club is Map) {
        final mapped = club.map((key, value) => MapEntry(key.toString(), value));
        if (mapped['is_active'] == true) {
          list.add({
            'id': mapped['id'],
            'name': mapped['name'],
            'role': row['role'],
          });
        }
      }
    }

    list.sort((a, b) => (a['name'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((b['name'] ?? '').toString().toLowerCase()));

    return list;
  }

  static Future<bool> canSwitchHostingClub() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final row = await supabase
        .from('user_entitlements')
        .select('status, ends_at')
        .eq('user_id', user.id)
        .eq('entitlement_key', 'multi_club_hosting')
        .maybeSingle();

    if (row == null) return false;

    final status = (row['status'] ?? '').toString().toLowerCase();
    if (status != 'active') return false;

    final endsAtRaw = row['ends_at']?.toString();
    if (endsAtRaw == null || endsAtRaw.isEmpty) return true;

    final endsAt = DateTime.tryParse(endsAtRaw);
    if (endsAt == null) return true;

    return DateTime.now().isBefore(endsAt.toLocal());
  }
}