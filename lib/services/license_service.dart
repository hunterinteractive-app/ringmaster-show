// lib/services/license_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class LicenseSnapshot {
  final int purchasedShowDays;
  final int consumedShowDays;
  final bool unlimitedAccess;
  final bool unlimitedActive;
  final DateTime? unlimitedExpiresAt;
  final bool canChangeHostClub;

  const LicenseSnapshot({
    required this.purchasedShowDays,
    required this.consumedShowDays,
    required this.unlimitedAccess,
    required this.unlimitedActive,
    required this.unlimitedExpiresAt,
    required this.canChangeHostClub,
  });

  int get remainingShowDays {
    final remaining = purchasedShowDays - consumedShowDays;
    return remaining < 0 ? 0 : remaining;
  }

  bool get hasUnlimitedActiveNow {
    if (!unlimitedAccess && !unlimitedActive) return false;

    if (unlimitedExpiresAt == null) {
      return unlimitedAccess || unlimitedActive;
    }

    return unlimitedExpiresAt!.isAfter(DateTime.now().toUtc());
  }

  bool get canCreateShows => hasUnlimitedActiveNow || remainingShowDays > 0;

  factory LicenseSnapshot.empty() {
    return const LicenseSnapshot(
      purchasedShowDays: 0,
      consumedShowDays: 0,
      unlimitedAccess: false,
      unlimitedActive: false,
      unlimitedExpiresAt: null,
      canChangeHostClub: false,
    );
  }

  factory LicenseSnapshot.fromMap(Map<String, dynamic> row) {
    return LicenseSnapshot(
      purchasedShowDays: (row['purchased_show_days'] as num?)?.toInt() ?? 0,
      consumedShowDays: (row['consumed_show_days'] as num?)?.toInt() ?? 0,
      unlimitedAccess: row['unlimited_access'] == true,
      unlimitedActive: row['unlimited_active'] == true,
      unlimitedExpiresAt: row['unlimited_expires_at'] == null
          ? null
          : DateTime.tryParse(row['unlimited_expires_at'].toString()),
      canChangeHostClub: row['can_change_host_club'] == true,
    );
  }
}

class LicenseService {
  LicenseService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<LicenseSnapshot> loadCurrentUserLicense() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return LicenseSnapshot.empty();

    final row = await _supabase
        .from('account_license_balances')
        .select(
          'purchased_show_days, consumed_show_days, unlimited_access, unlimited_active, unlimited_expires_at, can_change_host_club',
        )
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return LicenseSnapshot.empty();

    return LicenseSnapshot.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<bool> canSwitchHostingClub() async {
    final snapshot = await loadCurrentUserLicense();
    return snapshot.canChangeHostClub;
  }

  static Future<bool> canCreateShows() async {
    final snapshot = await loadCurrentUserLicense();
    return snapshot.canCreateShows;
  }

  static Future<int> remainingShowDays() async {
    final snapshot = await loadCurrentUserLicense();
    return snapshot.remainingShowDays;
  }
}