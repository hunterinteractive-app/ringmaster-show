import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/assistant_guide_catalog.dart';
import '../../services/assistant_guide_links.dart';

class AssistantAnswersScreen extends StatefulWidget {
  const AssistantAnswersScreen({super.key});
  @override
  State<AssistantAnswersScreen> createState() => _AssistantAnswersScreenState();
}

class _AssistantAnswersScreenState extends State<AssistantAnswersScreen> {
  final _rows = <Map<String, dynamic>>[];
  bool _busy = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) _rows.clear();
    });
    try {
      final data = await Supabase.instance.client.rpc(
        'chester_answer_admin',
        params: {'p_action': 'list', 'p_offset': _rows.length},
      );
      if (mounted) {
        setState(() {
          _rows.addAll((data as List).map((e) => Map<String, dynamic>.from(e)));
          _more = data.length == 50;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to load reviewed answers. Super Admin access and the database update are required.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chester Reviewed Answers')),
    backgroundColor: AppColors.pageBackground,
    body: DefaultTextStyle.merge(
      style: const TextStyle(color: Colors.white),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Turn useful conversations into reusable guidance',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Start with Create FAQ draft on a Chester reply in Conversations. Review the steps and privacy, then publish. Published answers are matched before AI is used.',
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (!_busy && _error == null && _rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No drafts yet. Start from a saved conversation.'),
            ),
          for (final row in _rows)
            Card(
              child: ListTile(
                title: Text(row['question']),
                subtitle: Text(
                  row['published_at'] == null
                      ? 'Draft • Not available to Chester'
                      : 'Published • Edits stay private until republished',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AssistantAnswerEditor(draft: row),
                    ),
                  );
                  if (mounted) _load(reset: true);
                },
              ),
            ),
          Wrap(
            children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _busy ? null : () => _load(reset: true),
                child: const Text('Refresh'),
              ),
              if (_more && _rows.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: _busy ? null : () => _load(),
                  child: const Text('Load more'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AssistantAnswerEditor extends StatefulWidget {
  const AssistantAnswerEditor({super.key, required this.draft});
  final Map<String, dynamic> draft;
  @override
  State<AssistantAnswerEditor> createState() => _AssistantAnswerEditorState();
}

class _AssistantAnswerEditorState extends State<AssistantAnswerEditor> {
  late Map<String, dynamic> _draft = Map.of(widget.draft);
  late final _question = TextEditingController(text: _draft['question']);
  late final _answer = TextEditingController(
    text: assistantVisibleAnswer(_draft['answer']),
  );
  late final _aliases = TextEditingController(
    text: (_draft['aliases'] as List).join('\n'),
  );
  late final Set<String> _guides = {
    for (final match in RegExp(
      r'\[\[guide:([^\]]+)\]\]',
    ).allMatches(_draft['answer']))
      if (assistantGuideCatalog.containsKey(match.group(1))) match.group(1)!,
  };
  bool _reviewed = false, _busy = false;
  String? _status;
  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _aliases.dispose();
    super.dispose();
  }

  void _changed(String _) {
    if (_reviewed) setState(() => _reviewed = false);
  }

  Future<void> _save(String action) async {
    setState(() => _busy = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'chester_answer_admin',
        params: {
          'p_action': action,
          'p_id': _draft['id'],
          'p_version': _draft['version'],
          'p_question': _question.text.trim(),
          'p_answer':
              _answer.text.trim() +
              _guides.map((id) => '\n\n[[guide:$id]]').join(),
          'p_aliases': _aliases.text
              .split('\n')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          'p_reviewed': _reviewed,
        },
      );
      if (mounted) {
        setState(() {
          _draft = Map<String, dynamic>.from(response as Map);
          _reviewed = false;
          _status = action == 'publish'
              ? 'Published. Chester can now reuse this answer.'
              : action == 'unpublish'
              ? 'Unpublished. Chester will no longer match this answer.'
              : 'Draft saved. Published content has not changed.';
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(
          () => _status = e.code == '23505'
              ? 'A matching question is already used by another published answer. Edit the matching questions.'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _status = 'Unable to save. Your edits are still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review FAQ draft')),
    backgroundColor: AppColors.surface,
    body: AppTheme.surfaceTextScope(
      context,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Publish general guidance only',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Remove names, emails, animal IDs, payment details, and personal entry status. Email addresses and UUIDs in the answer are removed automatically; review the question and all remaining details yourself. Use general questions beginning with “How do…”, “How can…”, “How to…”, “Where can…”, “Where do…”, or “What should…”.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _question,
            enabled: !_busy,
            onChanged: _changed,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Main question',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _aliases,
            enabled: !_busy,
            onChanged: _changed,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Other matching questions — one per line',
              helperText:
                  'Up to 20 exact variants. Capitalization and ending punctuation are ignored.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _answer,
            enabled: !_busy,
            onChanged: _changed,
            minLines: 8,
            maxLines: 18,
            maxLength: 15000,
            decoration: const InputDecoration(
              labelText: 'Reviewed answer and steps',
              helperText:
                  'Page names such as My Entries become navigation links in Chester.',
              border: OutlineInputBorder(),
            ),
          ),
          ExpansionTile(
            title: const Text('Step-by-step guide references'),
            children: [
              for (final entry in assistantGuideCatalog.entries)
                CheckboxListTile(
                  title: Text(entry.value['label']!),
                  value: _guides.contains(entry.key),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          if (value == true && _guides.length < 3) {
                            _guides.add(entry.key);
                          } else {
                            _guides.remove(entry.key);
                          }
                          _reviewed = false;
                        }),
                ),
            ],
          ),
          CheckboxListTile(
            value: _reviewed,
            onChanged: _busy
                ? null
                : (value) => setState(() => _reviewed = value == true),
            title: const Text(
              'I verified the steps and links, removed personal information, and confirmed this answer is safe for all users.',
            ),
          ),
          if (_status != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_status!)),
          if (_busy) const LinearProgressIndicator(),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _save('save'),
                child: const Text('Save draft'),
              ),
              FilledButton(
                onPressed: _busy || !_reviewed ? null : () => _save('publish'),
                child: Text(
                  _draft['published_at'] == null
                      ? 'Approve and publish'
                      : 'Approve and republish',
                ),
              ),
              if (_draft['published_at'] != null)
                TextButton(
                  onPressed: _busy ? null : () => _save('unpublish'),
                  child: const Text('Unpublish'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
