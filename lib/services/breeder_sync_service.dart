import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class BreederSyncService {
  static Future<void> refresh(String ownerId) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return;
    final response = await http
        .post(
          Uri.parse(
            'https://aqfsrolvaewcpkdkttiz.supabase.co/functions/v1/show-connection',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'action': 'pull', 'owner_id': ownerId}),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError(
        'Breeder animals could not refresh. Previously saved Show animals are still available.',
      );
    }
  }
}
