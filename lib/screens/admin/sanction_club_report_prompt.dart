import 'package:flutter/material.dart';
import 'package:ringmaster_show/services/sanction_club_report_service.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

Future<bool> showSanctionClubReportPrompt(
  BuildContext context, {
  required SanctionClubReportOption option,
  required Future<void> Function(void Function(String) onProgress) send,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Theme(
          data: AppTheme.surfaceDialogTheme(Theme.of(context)),
          child: _SanctionClubReportPrompt(option: option, send: send),
        ),
      ) ??
      false;
}

class _SanctionClubReportPrompt extends StatefulWidget {
  const _SanctionClubReportPrompt({required this.option, required this.send});

  final SanctionClubReportOption option;
  final Future<void> Function(void Function(String) onProgress) send;

  @override
  State<_SanctionClubReportPrompt> createState() =>
      _SanctionClubReportPromptState();
}

class _SanctionClubReportPromptState extends State<_SanctionClubReportPrompt> {
  String? _progress;
  bool _failed = false;

  Future<void> _send() async {
    setState(() {
      _failed = false;
      _progress = 'Preparing reports…';
    });
    try {
      await widget.send((message) {
        if (mounted) setState(() => _progress = message);
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final progress = _progress;
    return PopScope(
      canPop: progress == null,
      child: AlertDialog(
        title: Text('Generate and send ${option.clubName} reports?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your sanction numbers are saved.'),
              const SizedBox(height: 12),
              Text(
                '${option.reportCount} PDFs for ${option.sections.join(', ')}',
              ),
              const SizedBox(height: 4),
              Text('Send to ${option.recipient}'),
              if (progress != null) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Semantics(liveRegion: true, child: Text(progress)),
                const Text('Keep this dialog open until sending finishes.'),
              ],
              if (_failed) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: const Text(
                    'The report email couldn’t be confirmed. Try again or '
                    'check Report Delivery History in Closeout.',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: progress == null
                ? () => Navigator.of(context).pop(false)
                : null,
            child: Text(_failed ? 'Close' : 'Save Only'),
          ),
          FilledButton(
            onPressed: progress == null ? _send : null,
            child: Text(_failed ? 'Try Again' : 'Generate & Send'),
          ),
        ],
      ),
    );
  }
}
