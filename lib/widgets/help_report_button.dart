// lib/widgets/help_report_button.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpReportButton extends StatelessWidget {
  const HelpReportButton({
    super.key,
    this.pageTitle,
    this.pageRoute,
    this.showId,
    this.compact = false,
  });

  final String? pageTitle;
  final String? pageRoute;
  final String? showId;
  final bool compact;

  Future<void> _emailSupport(BuildContext context) async {
    final subject = pageTitle?.trim().isNotEmpty == true
        ? 'RingMaster Show help: ${pageTitle!.trim()}'
        : 'RingMaster Show help request';
    final opened = await launchUrl(
      Uri(
        scheme: 'mailto',
        path: 'support@ringmasterone.com',
        queryParameters: {'subject': subject},
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open your email app.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Report an issue',
        icon: const Icon(Icons.help_outline),
        onPressed: () => _emailSupport(context),
      );
    }

    return TextButton.icon(
      onPressed: () => _emailSupport(context),
      icon: const Icon(Icons.help_outline),
      label: const Text('Help'),
    );
  }
}
