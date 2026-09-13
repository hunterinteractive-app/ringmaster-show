import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Household data context only. Never use this identity for staff permissions,
/// legal acceptance, licenses, authentication, or audit attribution.
class HouseholdSession {
  static final selection = ValueNotifier<String?>(null);
  static String? _loginId;
  static List<Map<String, dynamic>> households = [];
  static List<Map<String, dynamic>> invitations = [];

  static String? get ownerUserId {
    final actor = Supabase.instance.client.auth.currentUser?.id;
    if (_loginId != actor) return actor;
    return selection.value ?? actor;
  }

  static Future<void> refresh({
    String action = 'list',
    String? id,
    String? email,
  }) async {
    final client = Supabase.instance.client;
    final actor = client.auth.currentUser?.id;
    if (_loginId != actor) {
      _loginId = actor;
      households = [];
      invitations = [];
      selection.value = null;
    }
    if (actor == null) return;
    final result = Map<String, dynamic>.from(
      await client.rpc(
            'household_access',
            params: {
              'p_action': action,
              'p_invitation_id': id,
              'p_email': email,
            },
          )
          as Map,
    );
    if (client.auth.currentUser?.id != actor) return;
    households = (result['households'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    invitations = (result['invitations'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!households.any((h) => h['owner_user_id'] == ownerUserId)) {
      selection.value = null;
    }
  }

  static Future<void> sendInvitation(String email) async {
    final response = await Supabase.instance.client.functions.invoke(
      'household-send-invitation',
      body: {'email': email.trim().toLowerCase()},
    );
    if (response.data is! Map || response.data['ok'] != true) {
      throw StateError('Invitation email could not be sent.');
    }
  }

  static void select(String owner) {
    if (!households.any((h) => h['owner_user_id'] == owner)) {
      throw StateError('This household is no longer available.');
    }
    selection.value = owner;
  }
}
