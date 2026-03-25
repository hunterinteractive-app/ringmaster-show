import 'package:supabase_flutter/supabase_flutter.dart';

class ClubService {
  static final SupabaseClient supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> loadMyClubs() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    final rows = await supabase
        .from('club_members')
        .select('club_id, role, is_active, clubs(id, name, slug)')
        .eq('user_id', user.id)
        .eq('is_active', true);

    final list = <Map<String, dynamic>>[];

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final club = row['clubs'];

      if (club is Map) {
        list.add({
          'id': club['id'],
          'name': club['name'],
          'slug': club['slug'],
          'role': row['role'],
        });
      }
    }

    return list;
  }

  static Future<Map<String, dynamic>?> getDefaultClub() async {
    final clubs = await loadMyClubs();
    if (clubs.isEmpty) return null;
    return clubs.first;
  }
}