import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Temporary account-settings visibility gate for the HerdMaster pilot.
/// The API still independently authenticates connection creation and consent.
class HerdMasterPilotLinkButton extends StatelessWidget {
  const HerdMasterPilotLinkButton({
    super.key,
    required this.user,
    required this.ownerUserId,
    required this.supportMode,
    required this.onPressed,
    this.partnerName = 'HerdMaster',
  });

  final String partnerName;
  final User? user;
  final String? ownerUserId;
  final bool supportMode;
  final VoidCallback onPressed;

  static bool canShow(User? user, String? ownerUserId, bool supportMode) =>
      !supportMode &&
      user != null &&
      user.emailConfirmedAt != null &&
      user.email?.trim().toLowerCase() == 'zaynetort2@gmail.com' &&
      ownerUserId == user.id;

  @override
  Widget build(BuildContext context) {
    if (!canShow(user, ownerUserId, supportMode)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.link),
        label: Text('Link $partnerName'),
      ),
    );
  }
}
