import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ringmaster_show/services/ringmaster_backend.dart';

import 'support_delegation.dart';

class BreederSyncService {
  static Future<void> refresh(String ownerId) async {
    final token = ringMasterClient.auth.currentSession?.accessToken;
    if (token == null) return;
    final payload = jsonEncode({'action': 'pull', 'owner_id': ownerId});
    final response = RingMasterData.delegated
        ? await RingMasterData.refreshBreederConnection(
            payload,
          ).timeout(const Duration(seconds: 25))
        : await http
              .post(
                Uri.parse(
                  'https://aqfsrolvaewcpkdkttiz.supabase.co/functions/v1/show-connection',
                ),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: payload,
              )
              .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError(
        'Breeder animals could not refresh. Previously saved Show animals are still available.',
      );
    }
  }
}
