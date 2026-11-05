import 'dart:async';
import 'package:flutter/foundation.dart';
import 'support_delegation.dart';
import 'support_tab.dart';

class SupportImpersonationSession {
  static final ValueNotifier<SupportImpersonatedUser?> current =
      ValueNotifier<SupportImpersonatedUser?>(null);

  static bool get isActive => current.value != null;

  static String? get targetUserId => current.value?.userId;

  static bool get readOnly => isActive && !RingMasterData.delegated;
  static Future<void> begin(SupportImpersonatedUser user) async {
    final grant = await RingMasterData.control('start', target: user.userId);
    if (grant['mode'] == 'preview') {
      start(user);
      return;
    }
    if (grant['user']?['id'] != user.userId) {
      throw StateError('Incorrect support account.');
    }
    if (restartSupportTab(grant['id'] as String)) return;
    await RingMasterData.attach(grant);
    start(user);
  }

  static Future<void> restore(String id) async {
    final grant = await RingMasterData.control('resume', session: id);
    await RingMasterData.attach(grant);
    final u = RingMasterData.client.auth.currentUser!;
    start(
      SupportImpersonatedUser(
        userId: u.id,
        email: u.email ?? '',
        displayName: u.userMetadata?['display_name']?.toString() ?? '',
        exhibitorName: '',
      ),
    );
  }

  @visibleForTesting
  static void start(SupportImpersonatedUser user) {
    current.value = user;
  }

  static Future<void> finish() async {
    if (RingMasterData.delegated) {
      try {
        await RingMasterData.end().timeout(const Duration(seconds: 8));
      } finally {
        if (!restartSupportTab(null)) {
          await RingMasterData.detach();
          stop();
        }
      }
    } else {
      stop();
    }
  }

  static void stop() {
    current.value = null;
  }
}

class SupportImpersonatedUser {
  const SupportImpersonatedUser({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.exhibitorName,
  });

  final String userId;
  final String email;
  final String displayName;
  final String exhibitorName;

  String get label {
    final cleanedExhibitor = exhibitorName.trim();
    if (cleanedExhibitor.isNotEmpty) return cleanedExhibitor;

    final cleanedDisplay = displayName.trim();
    final emailLocal = email.trim().isEmpty
        ? ''
        : email.trim().split('@').first.trim().toLowerCase();

    if (cleanedDisplay.isNotEmpty &&
        cleanedDisplay.toLowerCase() != emailLocal) {
      return cleanedDisplay;
    }

    if (email.trim().isNotEmpty) {
      final local = email.trim().split('@').first;
      final parts = local
          .replaceAll('.', ' ')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .split(' ')
          .where((p) => p.trim().isNotEmpty)
          .toList();

      if (parts.isNotEmpty) {
        return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
      }

      return email.trim();
    }

    return userId;
  }
}
