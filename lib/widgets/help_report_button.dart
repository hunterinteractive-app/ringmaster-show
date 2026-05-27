// lib/widgets/help_report_button.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/widgets/help_report_dialog.dart';

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

  Future<void> _openDialog(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => HelpReportDialog(
        pageTitle: pageTitle,
        pageRoute: pageRoute ?? ModalRoute.of(context)?.settings.name,
        showId: showId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Report an issue',
        icon: const Icon(Icons.help_outline),
        onPressed: () => _openDialog(context),
      );
    }

    return TextButton.icon(
      onPressed: () => _openDialog(context),
      icon: const Icon(Icons.help_outline),
      label: const Text('Help'),
    );
  }
}
