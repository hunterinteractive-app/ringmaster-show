import 'assistant_answers_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/assistant_guide_links.dart';
import '../../theme/app_theme.dart';

class AssistantConversationsScreen extends StatefulWidget {
  const AssistantConversationsScreen({
    super.key,
    this.conversationId,
    this.label,
    this.loadRows,
  });
  final String? conversationId;
  final String? label;
  final Future<List<dynamic>> Function(String? conversation, int offset)?
  loadRows;
  @override
  State<AssistantConversationsScreen> createState() =>
      _AssistantConversationsScreenState();
}

class _AssistantConversationsScreenState
    extends State<AssistantConversationsScreen> {
  final _rows = <Map<String, dynamic>>[];
  bool _busy = false, _more = true;
  String? _error;
  bool get _detail => widget.conversationId != null;
  @override
  void initState() {
    super.initState();
    _load();
  }

  String _date(dynamic value) =>
      DateTime.tryParse('$value')?.toLocal().toString().split('.').first ??
      '$value';
  Future<void> _load({bool refresh = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (refresh) {
        _rows.clear();
        _more = true;
      }
    });
    try {
      final result = widget.loadRows != null
          ? await widget.loadRows!(widget.conversationId, _rows.length)
          : await Supabase.instance.client.rpc(
              'chester_review',
              params: {
                'p_conversation': widget.conversationId,
                'p_offset': _rows.length,
              },
            );
      if (!mounted) return;
      final rows = (result as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _rows.addAll(rows);
        _more = rows.length == (_detail ? 100 : 50);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to load conversations. Super Admin access and the Chester database update are required.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createDraft(String messageId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final draft = await Supabase.instance.client.rpc(
        'chester_answer_admin',
        params: {'p_action': 'create', 'p_source': messageId},
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AssistantAnswerEditor(
            draft: Map<String, dynamic>.from(draft as Map),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to create draft. Check Super Admin access and the database update.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_detail ? 'Chat with Chester' : 'Chester Conversations'),
    ),
    backgroundColor: AppColors.pageBackground,
    body: Theme(
      data: AppTheme.onGradientTheme(Theme.of(context)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.label ?? 'Saved conversations',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _detail
                  ? 'Messages and FAQ activity in order • Times shown in your time zone'
                  : 'Review signed-in chats, prepared answers, AI replies, and opened FAQs.',
            ),
            if (_detail)
              SelectableText('Conversation: ${widget.conversationId}'),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ),
            if (!_busy && _error == null && _rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved conversations yet. New interactions appear after the database update is installed.',
                ),
              ),
            for (final row in _rows)
              if (!_detail)
                Card(
                  color: Colors.white.withValues(alpha: .10),
                  child: ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text('${row['email'] ?? row['actor_id']}'),
                    subtitle: Text(
                      '${row['preview'] ?? ''}\n${_date(row['updated_at'])} • ${row['message_count']} interactions',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AssistantConversationsScreen(
                          conversationId: row['id'] as String,
                          label: '${row['email'] ?? row['actor_id']}',
                        ),
                      ),
                    ),
                  ),
                )
              else
                Card(
                  color: Colors.white.withValues(alpha: .10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['role'] == 'user'
                              ? 'User'
                              : row['role'] == 'assistant'
                              ? 'Chester'
                              : 'Activity'} • ${row['source']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${_date(row['created_at'])} • ${row['page']} • ${row['topic']}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                        if (row['role'] == 'assistant')
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _createDraft(row['id'] as String),
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Create FAQ draft'),
                          ),
                        const SizedBox(height: 10),
                        SelectableText(
                          assistantVisibleAnswer(row['content'] as String),
                        ),
                        for (final link in assistantGuideLinks(
                          row['content'] as String,
                        ).entries)
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(link.value),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(link.key),
                          ),
                      ],
                    ),
                  ),
                ),
            Wrap(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _load(refresh: true),
                  child: const Text('Refresh'),
                ),
                if (_more && _rows.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
