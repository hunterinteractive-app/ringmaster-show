import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

class HelpReportsScreen extends StatefulWidget {
  const HelpReportsScreen({super.key});

  @override
  State<HelpReportsScreen> createState() => _HelpReportsScreenState();
}

class _HelpReportsScreenState extends State<HelpReportsScreen> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String _statusFilter = 'new';

  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = _statusFilter == 'all'
          ? await supabase
              .from('help_reports')
              .select()
              .order('created_at', ascending: false)
              .limit(100)
          : await supabase
              .from('help_reports')
              .select()
              .eq('status', _statusFilter)
              .order('created_at', ascending: false)
              .limit(100);

      if (!mounted) return;

      setState(() {
        _reports = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(
    Map<String, dynamic> report,
    String status,
  ) async {
    final id = report['id']?.toString();
    if (id == null || id.isEmpty) return;

    try {
      await supabase
          .from('help_reports')
          .update({'status': status})
          .eq('id', id);

      await _loadReports();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update report: $e')),
      );
    }
  }

  Future<void> _addMessage(
    Map<String, dynamic> report, {
    required String message,
    required bool isInternalNote,
  }) async {
    final reportId = report['id']?.toString();
    if (reportId == null || reportId.isEmpty) return;

    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final user = supabase.auth.currentUser;

    try {
      await supabase.from('help_report_messages').insert({
        'help_report_id': reportId,
        'sender_user_id': user?.id,
        'sender_email': user?.email,
        'sender_role': 'admin',
        'message': trimmed,
        'is_internal_note': isInternalNote,
      });

      final nextStatus = isInternalNote ? report['status']?.toString() ?? 'reviewing' : 'waiting_on_user';

      await supabase
          .from('help_reports')
          .update({
            'status': nextStatus,
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', reportId);

      await _loadReports();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add message: $e')),
      );
    }
  }

  void _openReport(Map<String, dynamic> report) {
    showDialog<void>(
      context: context,
      builder: (_) => _HelpReportDetailsDialog(
        report: report,
        onStatusChanged: (status) => _updateStatus(report, status),
        onAddMessage: ({required message, required isInternalNote}) =>
            _addMessage(
          report,
          message: message,
          isInternalNote: isInternalNote,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Help Reports',
      subtitle: 'Review submitted issue reports and troubleshooting details',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('New'),
                selected: _statusFilter == 'new',
                onSelected: (_) {
                  setState(() => _statusFilter = 'new');
                  _loadReports();
                },
              ),
              ChoiceChip(
                label: const Text('Reviewing'),
                selected: _statusFilter == 'reviewing',
                onSelected: (_) {
                  setState(() => _statusFilter = 'reviewing');
                  _loadReports();
                },
              ),
              ChoiceChip(
                label: const Text('Waiting on User'),
                selected: _statusFilter == 'waiting_on_user',
                onSelected: (_) {
                  setState(() => _statusFilter = 'waiting_on_user');
                  _loadReports();
                },
              ),
              ChoiceChip(
                label: const Text('Resolved'),
                selected: _statusFilter == 'resolved',
                onSelected: (_) {
                  setState(() => _statusFilter = 'resolved');
                  _loadReports();
                },
              ),
              ChoiceChip(
                label: const Text('All'),
                selected: _statusFilter == 'all',
                onSelected: (_) {
                  setState(() => _statusFilter = 'all');
                  _loadReports();
                },
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadReports,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          'Could not load help reports:\n$_error',
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_reports.isEmpty) {
      return const Center(
        child: Text('No help reports found.'),
      );
    }

    return ListView.separated(
      itemCount: _reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final report = _reports[index];

        final pageTitle = report['page_title']?.toString() ?? 'Unknown page';
        final message = report['message']?.toString() ?? '';
        final userEmail = report['user_email']?.toString() ?? 'Unknown user';
        final status = report['status']?.toString() ?? 'new';
        final createdAt = report['created_at']?.toString() ?? '';
        final createdDate = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
        final screenshotPath = report['screenshot_path']?.toString();

        return Card(
          child: ListTile(
            leading: Icon(
              screenshotPath == null || screenshotPath.isEmpty
                  ? Icons.report_problem_outlined
                  : Icons.image_outlined,
            ),
            title: Text(pageTitle),
            subtitle: Text(
              [
                userEmail,
                if (createdDate.isNotEmpty) createdDate,
                message,
              ].join('\n'),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: false,
            trailing: SizedBox(
              width: 88,
              child: Align(
                alignment: Alignment.centerRight,
                child: Chip(
                  label: Text(
                    status,
                    overflow: TextOverflow.ellipsis,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            onTap: () => _openReport(report),
          ),
        );
      },
    );
  }
}

class _HelpReportDetailsDialog extends StatefulWidget {
  const _HelpReportDetailsDialog({
    required this.report,
    required this.onStatusChanged,
    required this.onAddMessage,
  });

  final Map<String, dynamic> report;
  final ValueChanged<String> onStatusChanged;
  final Future<void> Function({
    required String message,
    required bool isInternalNote,
  }) onAddMessage;

  @override
  State<_HelpReportDetailsDialog> createState() => _HelpReportDetailsDialogState();
}

class _HelpReportDetailsDialogState extends State<_HelpReportDetailsDialog> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _replyController = TextEditingController();

  bool _loadingMessages = true;
  bool _sendingMessage = false;
  String? _messageError;
  List<Map<String, dynamic>> _messages = [];
  String? _signedScreenshotUrl;
  bool _loadingScreenshot = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadScreenshotUrl();
    }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _loadScreenshotUrl() async {
    final path = widget.report['screenshot_path']?.toString();

    if (path != null && path.trim().isNotEmpty) {
        setState(() => _loadingScreenshot = true);

        try {
        final signedUrl = await supabase.storage
            .from('help-report-screenshots')
            .createSignedUrl(path.trim(), 60 * 60);

        if (!mounted) return;
        setState(() {
            _signedScreenshotUrl = signedUrl;
            _loadingScreenshot = false;
        });
        return;
        } catch (_) {
        if (!mounted) return;
        setState(() => _loadingScreenshot = false);
        }
    }

    final existingUrl = widget.report['screenshot_url']?.toString();
    if (existingUrl != null && existingUrl.trim().isNotEmpty) {
        setState(() => _signedScreenshotUrl = existingUrl.trim());
    }
    }

  Future<void> _loadMessages() async {
    final reportId = widget.report['id']?.toString();
    if (reportId == null || reportId.isEmpty) {
      setState(() {
        _loadingMessages = false;
        _messages = [];
      });
      return;
    }

    setState(() {
      _loadingMessages = true;
      _messageError = null;
    });

    try {
      final rows = await supabase
          .from('help_report_messages')
          .select()
          .eq('help_report_id', reportId)
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        _messages = (rows as List).cast<Map<String, dynamic>>();
        _loadingMessages = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _messageError = e.toString();
        _loadingMessages = false;
      });
    }
  }

  Future<void> _sendMessage({required bool isInternalNote}) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sendingMessage = true);

    try {
      await widget.onAddMessage(
        message: text,
        isInternalNote: isInternalNote,
      );

      _replyController.clear();
      await _loadMessages();

      if (!mounted) return;
      setState(() => _sendingMessage = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingMessage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = widget.report['page_title']?.toString() ?? 'Unknown page';
    final message = widget.report['message']?.toString() ?? '';
    final userEmail = widget.report['user_email']?.toString() ?? 'Unknown user';
    final showId = widget.report['show_id']?.toString();
    final status = widget.report['status']?.toString() ?? 'new';
    final screenshotUrl = widget.report['screenshot_url']?.toString();
    final screenshotPath = widget.report['screenshot_path']?.toString();
    final effectiveScreenshotUrl = _signedScreenshotUrl ??
        ((screenshotUrl != null && screenshotUrl.trim().isNotEmpty)
            ? screenshotUrl.trim()
            : null);
    final deviceInfo = widget.report['device_info'];

    return AlertDialog(
      title: Text(pageTitle),
      content: SizedBox(
        width: 820,
        height: MediaQuery.of(context).size.height * 0.75,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Status: $status')),
                  if (screenshotPath != null && screenshotPath.isNotEmpty)
                    const Chip(
                      avatar: Icon(Icons.image_outlined, size: 18),
                      label: Text('Screenshot attached'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _detail('User', userEmail),
              if (showId != null && showId.isNotEmpty) _detail('Show ID', showId),
              _detail('Page route', widget.report['page_route']?.toString() ?? ''),
              _detail('Created', widget.report['created_at']?.toString() ?? ''),
              _detail('Workflow version', widget.report['workflow_version']?.toString() ?? ''),
              _detail('App version', widget.report['app_version']?.toString() ?? ''),
              _detail('Build number', widget.report['build_number']?.toString() ?? ''),
              _detail('Platform', widget.report['platform']?.toString() ?? ''),
              _detail('OS', widget.report['operating_system']?.toString() ?? ''),
              const SizedBox(height: 16),
              const Text(
                'Original Message',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              SelectableText(message),
              const SizedBox(height: 16),
              if (effectiveScreenshotUrl != null &&
                    effectiveScreenshotUrl.isNotEmpty) ...[
                const Text(
                    'Screenshot',
                    style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                    constraints: const BoxConstraints(maxHeight: 420),
                    decoration: BoxDecoration(
                        border: Border.all(color: Color(0xFFE0E0E0)),
                        borderRadius: BorderRadius.circular(12),
                    ),
                    child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.network(
                        effectiveScreenshotUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator()),
                            );
                        },
                        errorBuilder: (context, error, stackTrace) {
                            return SizedBox(
                            height: 160,
                            child: Center(
                                child: Text(
                                'Could not load screenshot image.'
                                '${screenshotPath == null || screenshotPath.isEmpty ? '' : ' Path: $screenshotPath'}',
                                textAlign: TextAlign.center,
                                ),
                            ),
                            );
                        },
                        ),
                    ),
                    ),
                ),
                ] else if (_loadingScreenshot) ...[
                const Text(
                    'Screenshot',
                    style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                ),
                ] else if (screenshotPath != null && screenshotPath.isNotEmpty) ...[
                const Text(
                    'Screenshot',
                    style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SelectableText('Screenshot saved at: $screenshotPath'),
                ],
              const SizedBox(height: 16),
              const Divider(),
              const Text(
                'Conversation',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildMessages(),
              const SizedBox(height: 12),
              TextField(
                controller: _replyController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Reply or internal note',
                  hintText: 'Type a message back to the user, or add an internal note...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _sendingMessage
                        ? null
                        : () => _sendMessage(isInternalNote: false),
                    icon: const Icon(Icons.reply),
                    label: const Text('Reply to User'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _sendingMessage
                        ? null
                        : () => _sendMessage(isInternalNote: true),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Add Internal Note'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const Text(
                'Device Info',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(deviceInfo?.toString() ?? '{}'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onStatusChanged('new');
            Navigator.of(context).pop();
          },
          child: const Text('Mark New'),
        ),
        TextButton(
          onPressed: () {
            widget.onStatusChanged('reviewing');
            Navigator.of(context).pop();
          },
          child: const Text('Mark Reviewing'),
        ),
        TextButton(
          onPressed: () {
            widget.onStatusChanged('waiting_on_user');
            Navigator.of(context).pop();
          },
          child: const Text('Waiting on User'),
        ),
        FilledButton(
          onPressed: () {
            widget.onStatusChanged('resolved');
            Navigator.of(context).pop();
          },
          child: const Text('Mark Resolved'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildMessages() {
    if (_loadingMessages) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_messageError != null) {
      return Text(
        'Could not load messages: $_messageError',
        style: const TextStyle(color: Colors.red),
      );
    }

    if (_messages.isEmpty) {
      return const Text('No replies yet.');
    }

    return Column(
      children: _messages.map((message) {
        final senderRole = message['sender_role']?.toString() ?? 'user';
        final senderEmail = message['sender_email']?.toString() ?? 'Unknown sender';
        final body = message['message']?.toString() ?? '';
        final createdAt = message['created_at']?.toString() ?? '';
        final isInternal = message['is_internal_note'] == true;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      senderRole == 'admin' ? 'RingMaster Support' : senderEmail,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (isInternal)
                      const Chip(
                        label: Text('Internal'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (createdAt.isNotEmpty)
                      Text(
                        createdAt,
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(body),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _detail(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}