// lib/widgets/help_report_button.dart

import 'package:flutter/material.dart';
import '../services/show_assistant_service.dart';

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

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Ask Chester',
        icon: const Icon(Icons.help_outline),
        onPressed: () => ShowAssistantController.instance.open(
          title: pageTitle,
          showId: showId,
        ),
      );
    }

    return TextButton.icon(
      onPressed: () => ShowAssistantController.instance.open(
        title: pageTitle,
        showId: showId,
      ),
      icon: const Icon(Icons.help_outline),
      label: const Text('Help'),
    );
  }
}
