import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

class ReportEmailConfirmation {
  const ReportEmailConfirmation({
    required this.forceResend,
    required this.message,
  });
  final bool forceResend;
  final String message;
}

Future<ReportEmailConfirmation?> showReportEmailConfirmation(
  BuildContext context, {
  required String title,
  required String description,
  String sendLabel = 'Send Email',
  String initialMessage = '',
  bool bulk = false,
}) => showDialog<ReportEmailConfirmation>(
  context: context,
  builder: (context) => Theme(
    data: AppTheme.surfaceDialogTheme(Theme.of(context)),
    child: _ReportEmailConfirmationDialog(
      title: title,
      description: description,
      sendLabel: sendLabel,
      initialMessage: initialMessage,
      bulk: bulk,
    ),
  ),
);

class _ReportEmailConfirmationDialog extends StatefulWidget {
  const _ReportEmailConfirmationDialog({
    required this.title,
    required this.description,
    required this.sendLabel,
    required this.initialMessage,
    required this.bulk,
  });
  final String title, description, sendLabel, initialMessage;
  final bool bulk;

  @override
  State<_ReportEmailConfirmationDialog> createState() => _DialogState();
}

class _DialogState extends State<_ReportEmailConfirmationDialog> {
  late final _message = TextEditingController(text: widget.initialMessage);
  bool _resend = false;
  bool _missingMessage = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    final message = _message.text.trim();
    if (_resend && widget.bulk && message.isEmpty) {
      setState(() => _missingMessage = true);
      return;
    }
    Navigator.of(
      context,
    ).pop(ReportEmailConfirmation(forceResend: _resend, message: message));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 12),
            Text(
              _resend
                  ? 'Previously sent reports will be included. Add a message explaining the resend.'
                  : 'Reports already sent will be skipped, including regenerated reports.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Resend reports already sent'),
              value: _resend,
              onChanged: (value) => setState(() {
                _resend = value ?? false;
                _missingMessage = false;
              }),
            ),
            TextField(
              controller: _message,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: _resend && widget.bulk
                    ? 'Message (required)'
                    : 'Message (optional)',
                helperText: 'Included in every email sent with this action.',
                helperMaxLines: 2,
                errorText: _missingMessage
                    ? 'Add a message explaining why these reports are being resent.'
                    : null,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(_resend ? 'Resend Reports' : widget.sendLabel),
      ),
    ],
  );
}
