// lib/widgets/help_report_dialog.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/services/help_report_service.dart';

class HelpReportDialog extends StatefulWidget {
  const HelpReportDialog({
    super.key,
    this.pageTitle,
    this.pageRoute,
    this.showId,
  });

  final String? pageTitle;
  final String? pageRoute;
  final String? showId;

  @override
  State<HelpReportDialog> createState() => _HelpReportDialogState();
}

class _HelpReportDialogState extends State<HelpReportDialog> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();

    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a quick description first.')),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      await HelpReportService.submitReport(
        message: message,
        pageTitle: widget.pageTitle,
        pageRoute: widget.pageRoute,
        showId: widget.showId,
        context: context,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — your help report was sent.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _sending = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send help report: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report an Issue'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tell us what went wrong. RingMaster will automatically include useful troubleshooting details like device type, OS, app version, and page.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              maxLines: 6,
              minLines: 4,
              decoration: const InputDecoration(
                labelText: 'What is wrong?',
                hintText: 'Example: I clicked Print Control Sheets and got a red error...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(_sending ? 'Sending...' : 'Send Report'),
        ),
      ],
    );
  }
}