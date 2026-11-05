import 'package:ringmaster_show/services/ringmaster_backend.dart';

class FinalAwardAccessService {
  static Future<bool> canConfigureBestOpposite(String showId) async {
    try {
      return await ringMasterClient.rpc(
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
