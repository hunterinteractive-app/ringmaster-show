// lib/screens/my_help_requests_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/app_session.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

class MyHelpRequestsScreen extends StatefulWidget {
  const MyHelpRequestsScreen({super.key});

  @override
  State<MyHelpRequestsScreen> createState() => _MyHelpRequestsScreenState();
}

class _MyHelpRequestsScreenState extends State<MyHelpRequestsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final user = supabase.auth.currentUser;
    final effectiveUserId = AppSession.effectiveUserId ?? user?.id;

    if (user == null || effectiveUserId == null || effectiveUserId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view help requests.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await supabase
          .from('help_reports')
          .select()
          .eq('user_id', effectiveUserId)
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

  Future<void> _addUserReply(
    Map<String, dynamic> report, {
    required String message,
  }) async {
    final user = supabase.auth.currentUser;
    final reportId = report['id']?.toString();
    final trimmed = message.trim();

    if (AppSession.isSupportMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Replies are disabled while viewing as another user.'),
        ),
      );
      return;
    }

    if (user == null ||
        reportId == null ||
        reportId.isEmpty ||
        trimmed.isEmpty) {
      return;
    }

    try {
      await supabase.from('help_report_messages').insert({
        'help_report_id': reportId,
        'sender_user_id': user.id,
        'sender_email': user.email,
        'sender_role': 'user',
        'message': trimmed,
        'is_internal_note': false,
      });

      await supabase
          .from('help_reports')
          .update({
            'status': 'reviewing',
            'last_message_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', reportId);

      await _loadReports();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send reply: $e')));
    }
  }

  void _openReport(Map<String, dynamic> report) {
    showDialog<void>(
      context: context,
      builder: (_) => _MyHelpRequestDetailsDialog(
        report: report,
        readOnly: AppSession.isSupportMode,
        onReply: (message) => _addUserReply(report, message: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'My Help Requests',
      subtitle:
          'View your submitted issues and replies from RingMaster support',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTheme.gradientTextScope(
            context,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'These are the help requests you have submitted. Open one to view the status, support replies, and send a follow-up message.',
                    style: TextStyle(
                      color: AppColors.headerForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loadReports,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildBody()),
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
          'Could not load help requests:\n$_error',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.headerForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (_reports.isEmpty) {
      return const Center(
        child: Text(
          'You have not submitted any help requests yet.',
          style: TextStyle(
            color: AppColors.headerForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _reports.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final report = _reports[index];
        final pageTitle = report['page_title']?.toString() ?? 'Help request';
        final message = report['message']?.toString() ?? '';
        final status = report['status']?.toString() ?? 'new';
        final createdAt = report['created_at']?.toString() ?? '';
        final createdDate = createdAt.length >= 10
            ? createdAt.substring(0, 10)
            : createdAt;

        return AppTheme.surfaceTextScope(
          context,
          child: Card(
            color: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.headerForeground),
            ),
            child: ListTile(
              leading: _StatusIcon(status: status),
              title: Text(
                pageTitle,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                [if (createdDate.isNotEmpty) createdDate, message].join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: SizedBox(
                width: 118,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Chip(
                    backgroundColor: AppColors.neutralBadgeBg,
                    side: const BorderSide(color: AppColors.headerForeground),
                    label: Text(
                      _statusLabel(status),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              onTap: () => _openReport(report),
            ),
          ),
        );
      },
    );
  }
}

class _MyHelpRequestDetailsDialog extends StatefulWidget {
  const _MyHelpRequestDetailsDialog({
    required this.report,
    required this.readOnly,
    required this.onReply,
  });

  final Map<String, dynamic> report;
  final bool readOnly;
  final Future<void> Function(String message) onReply;

  @override
  State<_MyHelpRequestDetailsDialog> createState() =>
      _MyHelpRequestDetailsDialogState();
}

class _MyHelpRequestDetailsDialogState
    extends State<_MyHelpRequestDetailsDialog> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _replyController = TextEditingController();

  bool _loadingMessages = true;
  bool _sendingReply = false;
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
          .eq('is_internal_note', false)
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

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sendingReply = true);

    try {
      await widget.onReply(text);
      _replyController.clear();
      await _loadMessages();

      if (!mounted) return;
      setState(() => _sendingReply = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reply sent.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingReply = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send reply: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = widget.report['page_title']?.toString() ?? 'Help request';
    final message = widget.report['message']?.toString() ?? '';
    final status = widget.report['status']?.toString() ?? 'new';
    final createdAt = widget.report['created_at']?.toString() ?? '';
    final screenshotPath = widget.report['screenshot_path']?.toString();

    return AppTheme.surfaceTextScope(
      context,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(pageTitle),
        content: SizedBox(
          width: 720,
          height: MediaQuery.of(context).size.height * 0.7,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Status: ${_statusLabel(status)}')),
                    if (createdAt.isNotEmpty) Chip(label: Text(createdAt)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Original Message',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  message,
                  style: const TextStyle(color: AppColors.text),
                ),
                const SizedBox(height: 16),
                if (_signedScreenshotUrl != null &&
                    _signedScreenshotUrl!.isNotEmpty) ...[
                  const Text(
                    'Screenshot',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 360),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.headerForeground),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.network(
                          _signedScreenshotUrl!,
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
                                  style: const TextStyle(color: AppColors.text),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else if (_loadingScreenshot) ...[
                  const Text(
                    'Screenshot',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  const SizedBox(height: 16),
                ],
                const Divider(),
                const Text(
                  'Conversation',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildMessages(),
                const SizedBox(height: 12),
                TextField(
                  controller: _replyController,
                  readOnly: widget.readOnly,
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Reply',
                    hintText: widget.readOnly
                        ? 'Replies are disabled while viewing as another user.'
                        : 'Type a follow-up message...',
                    border: const OutlineInputBorder(),
                    labelStyle: const TextStyle(color: AppColors.muted),
                    hintStyle: const TextStyle(color: AppColors.muted),
                  ),
                ),
                if (widget.readOnly) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Support mode is read-only. Exit impersonation to reply as yourself.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.readOnly || _sendingReply
                      ? null
                      : _sendReply,
                  icon: _sendingReply
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sendingReply ? 'Sending...' : 'Send Reply'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
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
        style: const TextStyle(
          color: AppColors.danger,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (_messages.isEmpty) {
      return const Text(
        'No replies yet.',
        style: TextStyle(color: AppColors.muted),
      );
    }

    return Column(
      children: _messages.map((message) {
        final senderRole = message['sender_role']?.toString() ?? 'user';
        final senderEmail =
            message['sender_email']?.toString() ?? 'Unknown sender';
        final body = message['message']?.toString() ?? '';
        final createdAt = message['created_at']?.toString() ?? '';
        final isSupport = senderRole == 'admin';

        return AppTheme.surfaceTextScope(
          context,
          child: Card(
            color: AppColors.headerForeground,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              side: BorderSide(color: AppColors.muted.withValues(alpha: .22)),
            ),
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
                        isSupport ? 'RingMaster Support' : senderEmail,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (createdAt.isNotEmpty)
                        Text(
                          createdAt,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    body,
                    style: const TextStyle(color: AppColors.text),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case 'resolved':
        return const Icon(Icons.check_circle_outline);
      case 'waiting_on_user':
        return const Icon(Icons.mark_email_unread_outlined);
      case 'reviewing':
        return const Icon(Icons.rate_review_outlined);
      case 'new':
      default:
        return const Icon(Icons.help_outline);
    }
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'reviewing':
      return 'Reviewing';
    case 'waiting_on_user':
      return 'Waiting on You';
    case 'resolved':
      return 'Resolved';
    case 'closed':
      return 'Closed';
    case 'new':
    default:
      return 'New';
  }
}
