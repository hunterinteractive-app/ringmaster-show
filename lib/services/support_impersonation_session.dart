import 'package:flutter/foundation.dart';

class SupportImpersonationSession {
  static final ValueNotifier<SupportImpersonatedUser?> current =
      ValueNotifier<SupportImpersonatedUser?>(null);

  static bool get isActive => current.value != null;

  static String? get targetUserId => current.value?.userId;

  static void start(SupportImpersonatedUser user) {
    current.value = user;
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
