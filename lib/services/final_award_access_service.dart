import 'package:supabase_flutter/supabase_flutter.dart';

class FinalAwardAccessService {
  static Future<bool> canConfigureBestOpposite(String showId) async {
    try {
      return await Supabase.instance.client.rpc(
            'can_configure_best_opposite_final_award',
            params: {'p_show_id': showId},
          ) ==
          true;
    } on PostgrestException {
      // Keep the restricted option hidden until its migration is available.
      return false;
    }
  }
}
