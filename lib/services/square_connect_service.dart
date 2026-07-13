import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

class SquareConnectService {
  SquareConnectService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<String> startConnection(String showId) async {
    final data = await _invoke('square-connect-start', {'show_id': showId});
    final url = (data['authorization_url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw Exception('Square authorization URL was not returned.');
    }
    return url;
  }

  static Future<Map<String, dynamic>> getStatus(String showId) async {
    if (_supabase.auth.currentUser == null) throw Exception('Not signed in.');
    final response = await _supabase.functions.invoke(
      'square-connect-status',
      body: {'show_id': showId},
    );
    final data = _normalizeMap(response.data);
    if (response.status >= 200 && response.status < 300) return data;
    if ((data['status'] ?? '').toString().isNotEmpty) return data;
    final error = (data['error'] ?? '').toString().trim();
    throw Exception(error.isEmpty ? 'Square status request failed.' : error);
  }

  static Future<Map<String, dynamic>> selectLocation({
    required String showId,
    required String locationId,
  }) {
    return _invoke('square-connect-select-location', {
      'show_id': showId,
      'location_id': locationId,
    });
  }

  static Future<void> disconnect(String showId) async {
    await _invoke('square-disconnect', {'show_id': showId});
  }

  static Future<Map<String, dynamic>> _invoke(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    if (_supabase.auth.currentUser == null) throw Exception('Not signed in.');
    final response = await _supabase.functions.invoke(functionName, body: body);
    final data = _normalizeMap(response.data);
    if (response.status < 200 || response.status >= 300) {
      final error = (data['error'] ?? '').toString().trim();
      throw Exception(
        error.isEmpty ? 'Square connection request failed.' : error,
      );
    }
    return data;
  }

  static Map<String, dynamic> _normalizeMap(dynamic raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return <String, dynamic>{};
  }
}
