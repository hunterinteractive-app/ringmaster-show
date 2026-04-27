// lib/services/show_lock_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowLockService {
  static Future<bool> isShowLocked(String showId) async {
    final row = await supabase
        .from('shows')
        .select('is_locked')
        .eq('id', showId)
        .maybeSingle();

    return row?['is_locked'] == true;
  }

  static Future<void> assertShowUnlocked(String showId) async {
    final locked = await isShowLocked(showId);

    if (locked) {
      throw Exception(
        'This show is locked. Unlock the show before making changes.',
      );
    }
  }

  static Future<void> lockShow(String showId) async {
    await supabase.rpc('lock_show', params: {
      'p_show_id': showId,
    });
  }

  static Future<void> unlockShow(String showId) async {
    await supabase.rpc('unlock_show', params: {
      'p_show_id': showId,
    });
  }
}