import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/legal_config.dart';

/// Account-bound acceptance, confirmed by the database. Navigation checks share
/// one pending prompt; completed receipts are read afresh on later navigation.
class LegalAcceptanceService {
  LegalAcceptanceService(this.client, this.userId);

  final SupabaseClient client;
  final String userId;
  static final _pending = <(SupabaseClient, String), Future<bool?>>{};
  static const _columns =
      'user_id,accepted_terms_version,accepted_terms_at,'
      'accepted_privacy_version,accepted_privacy_at';

  static bool isCurrent(Map<String, dynamic>? row) {
    bool covers(Object? accepted, String required, List<String> versions) {
      if (accepted == required) return true;
      final index = versions.indexOf(accepted?.toString() ?? '');
      final requiredIndex = versions.indexOf(required);
      return requiredIndex >= 0 && index >= requiredIndex;
    }

    return covers(
          row?['accepted_terms_version'],
          LegalConfig.currentTermsVersion,
          LegalConfig.termsVersions,
        ) &&
        covers(
          row?['accepted_privacy_version'],
          LegalConfig.currentPrivacyVersion,
          LegalConfig.privacyVersions,
        );
  }

  void _requireSameAccount() {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('The signed-in account changed.');
    }
  }

  Future<Map<String, dynamic>?> read() async {
    _requireSameAccount();
    final row = await client
        .from('profiles')
        .select(_columns)
        .eq('user_id', userId)
        .maybeSingle();
    _requireSameAccount();
    return row;
  }

  Future<void> save() async {
    // Another page or device may have already recorded the same agreement.
    if (isCurrent(await read())) return;
    _requireSameAccount();
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      final row = await client
          .from('profiles')
          .upsert({
            'user_id': userId,
            'accepted_terms_version': LegalConfig.currentTermsVersion,
            'accepted_terms_at': now,
            'accepted_privacy_version': LegalConfig.currentPrivacyVersion,
            'accepted_privacy_at': now,
          }, onConflict: 'user_id')
          .select(_columns)
          .single();
      _requireSameAccount();
      if (row['user_id'] != userId || !isCurrent(row)) {
        throw StateError('The saved agreement could not be confirmed.');
      }
    } catch (error, stack) {
      // A response can be lost after the transaction commits. Confirm the
      // receipt before asking the person to retry a save they already made.
      try {
        if (isCurrent(await read())) return;
      } catch (_) {
        // Preserve the original save failure, without claiming success.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<bool?> ensureAccepted({
    required Future<bool?> Function(Future<void> Function() save) prompt,
  }) async {
    _requireSameAccount();
    final key = (client, userId);
    final existing = _pending[key];
    if (existing != null) return existing;
    final check = _checkAndPrompt(prompt);
    _pending[key] = check;
    try {
      return await check;
    } finally {
      if (identical(_pending[key], check)) _pending.remove(key);
    }
  }

  Future<bool?> _checkAndPrompt(
    Future<bool?> Function(Future<void> Function()) prompt,
  ) async {
    if (isCurrent(await read())) return true;
    final result = await prompt(save);
    _requireSameAccount();
    return result;
  }
}
