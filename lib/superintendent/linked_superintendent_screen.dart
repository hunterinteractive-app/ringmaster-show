import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_session.dart';
import '../theme/app_theme.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'linked_workspace_data.dart';
import 'superintendent_lineup_screen.dart';

class LinkedSuperintendentScreen extends StatefulWidget {
  final String workspaceId;
  final String name;
  final List<Map<String, dynamic>> shows;
  const LinkedSuperintendentScreen({
    super.key,
    required this.workspaceId,
    required this.name,
    required this.shows,
  });
  @override
  State<LinkedSuperintendentScreen> createState() =>
      _LinkedSuperintendentScreenState();
}

class _LinkedSuperintendentScreenState
    extends State<LinkedSuperintendentScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>>? _sections;
  List<Map<String, dynamic>> _counts = [];
  List<Map<String, dynamic>> _judges = [];
  List<Map<String, dynamic>> _assignments = [];
  String? _error;
  bool _loading = false;
  bool _editing = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_editing) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      // Check group visibility on every refresh, including permission revocation.
      await _client
          .from('superintendent_workspaces')
          .select('id')
          .eq('id', widget.workspaceId)
          .single();
      final data = await Future.wait(
        widget.shows.map((show) async {
          final id = show['id'].toString();
          final results = await Future.wait<dynamic>([
            _client
                .from('show_sections')
                .select('id,show_id,display_name,kind,letter')
                .eq('show_id', id)
                .order('display_name'),
            _client.rpc(
              'get_show_lineup_breed_counts',
              params: {'p_show_id': id},
            ),
            _client.rpc('get_show_judging_lineup', params: {'p_show_id': id}),
            _client.rpc('get_show_lineup_judges', params: {'p_show_id': id}),
          ]);
          return results
              .map((r) => List<Map<String, dynamic>>.from(r as List))
              .toList();
        }),
      );
      if (!mounted) return;
      setState(() {
        _sections = data.expand((d) => d[0]).toList();
        _counts = data.expand((d) => d[1]).toList();
        _judges = [
          for (var i = 0; i < data.length; i++)
            for (final judge in data[i][3])
              if (judge['is_enabled'] != false)
                {...judge, 'show_id': widget.shows[i]['id']},
        ];
        _assignments = data.expand((d) => d[2]).toList();
        _assignments.sort((a, b) {
          final order = ((a['sort_order'] ?? 0) as num).compareTo(
            (b['sort_order'] ?? 0) as num,
          );
          if (order != 0) return order;
          return '${a['show_id']}/${a['id']}'.compareTo(
            '${b['show_id']}/${b['id']}',
          );
        });
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to refresh the shared workspace. $e';
        });
      }
    } finally {
      _loading = false;
    }
  }

  String _showName(dynamic id) =>
      widget.shows.firstWhere((s) => s['id'] == id)['name'].toString();
  String _sectionName(Map<String, dynamic> row) {
    final sections = (_sections ?? []).where(
      (s) => s['id'] == row['section_id'],
    );
    return sections.isEmpty
        ? 'All sections / judge change'
        : (sections.first['display_name'] ??
                  '${sections.first['kind']} ${sections.first['letter']}')
              .toString();
  }

  String _status(dynamic raw) => switch (raw) {
    'completed' => 'Complete',
    'in_progress' => 'Judging',
    _ => 'Planned',
  };

  Future<void> _openLineup() async {
    _editing = true;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SuperintendentLineupScreen(
          showId: widget.shows.first['id'].toString(),
          showName: widget.name,
          workspaceId: widget.workspaceId,
          linkedShows: {
            for (final show in widget.shows)
              show['id'].toString(): show['name'].toString(),
          },
          readOnly: AppSession.isSupportMode,
        ),
      ),
    );
    _editing = false;
    await _load();
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    if (AppSession.isSupportMode || _error != null) return;
    _editing = true;
    final table = TextEditingController(
      text: (row['table_number'] ?? '').toString(),
    );
    final order = TextEditingController(
      text: (row['sort_order'] ?? 0).toString(),
    );
    var status = ['draft', 'in_progress', 'completed'].contains(row['status'])
        ? row['status'].toString()
        : 'draft';
    var saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${row['breed_id']} — ${_sectionName(row)}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_showName(row['show_id'])),
                  const SizedBox(height: 16),
                  TextField(
                    controller: table,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: 'Shared table number',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: order,
                    enabled: !saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Order at this table',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Judging progress',
                    ),
                    items: ['draft', 'in_progress', 'completed']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(_status(s)),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (v) => setDialogState(() => status = v!),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final position = int.tryParse(order.text);
                      if (position == null || position < 0) {
                        setDialogState(
                          () => error = 'Enter an order of zero or higher.',
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _client.rpc(
                          'save_workspace_assignment',
                          params: {
                            'p_workspace_id': widget.workspaceId,
                            'p_id': row['id'],
                            'p_table': table.text.trim(),
                            'p_order': position,
                            'p_status': status,
                            'p_expected_updated_at': row['updated_at'],
                          },
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                            error = e is PostgrestException
                                ? e.message
                                : e.toString();
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
    // Controllers are retained until the closing dialog finishes its animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    table.dispose();
    order.dispose();
    _editing = false;
    if (mounted) await _load();
  }

  Widget _card(Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: AppTheme.surfaceTextScope(context, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final totals = workspaceBreedTotals(_counts);
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final row in _assignments) {
      final table = (row['table_number'] ?? '').toString().trim();
      tables
          .putIfAbsent(table.isEmpty ? 'Unassigned' : table, () => [])
          .add(row);
    }
    final judges = <String, List<Map<String, dynamic>>>{};
    for (final judge in _judges) {
      judges.putIfAbsent(judge['judge_id'].toString(), () => []).add(judge);
    }
    final tableNames = tables.keys.toList()
      ..sort(
        (a, b) => (int.tryParse(a) != null && int.tryParse(b) != null)
            ? int.parse(a).compareTo(int.parse(b))
            : a.compareTo(b),
      );
    return RingMasterPageShell(
      title: 'Show Superintendent',
      subtitle: widget.name,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh both shows',
        ),
      ],
      body: _sections == null && _error == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_error != null)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if (AppSession.isSupportMode)
                  _card(
                    const Text(
                      'Support Mode — shared logistics are view-only.',
                    ),
                  ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Both shows · ${_sections?.length ?? 0} sections',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Counts and table planning are shared here. Each show keeps its own entries, results, and reports. Refreshes every 20 seconds.',
                      ),
                      const SizedBox(height: 12),
                      for (final show in widget.shows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                show['name'].toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  for (final section in (_sections ?? []).where(
                                    (s) => s['show_id'] == show['id'],
                                  ))
                                    Chip(
                                      label: Text(
                                        (section['display_name'] ??
                                                '${section['kind']} ${section['letter']}')
                                            .toString(),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _error != null ? null : _openLineup,
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Open shared Judging Line-Up'),
                      ),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Breed counts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text(
                        'Active entries, excluding scratches. Totals count each section entry, not unique animals.',
                      ),
                      const SizedBox(height: 8),
                      _countRow('All breeds', {
                        for (final section in _sections ?? [])
                          '${section['show_id']}/${section['id']}': _counts
                              .where((r) => r['section_id'] == section['id'])
                              .fold<int>(
                                0,
                                (sum, r) =>
                                    sum + (r['entry_count'] as num).toInt(),
                              ),
                      }),
                      for (final entry in totals.entries)
                        _countRow(entry.key, entry.value),
                      if (totals.isEmpty) const Text('No active entries yet.'),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Judges across both shows',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text(
                        'Each judge is listed once. Judges enabled in both shows are available in the shared Judging Line-Up.',
                      ),
                      for (final rows in judges.values)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            (rows.first['judge_name'] ?? 'Unnamed judge')
                                .toString(),
                          ),
                          subtitle: Text(
                            rows
                                .map((r) => _showName(r['show_id']))
                                .toSet()
                                .join('\n'),
                          ),
                        ),
                      if (judges.isEmpty) const Text('No enabled judges yet.'),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared table board',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Text(
                        'Use the shared Judging Line-Up to assign judges and breeds, arrange tables, Auto Fill, sync, and publish both shows together.',
                      ),
                      Text(
                        '${_assignments.where((r) => r['status'] == 'completed' && r['is_judge_change'] != true).length} of ${_assignments.where((r) => r['is_judge_change'] != true).length} breed assignments complete',
                      ),
                    ],
                  ),
                ),
                for (final name in tableNames)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == 'Unassigned' ? name : 'Table $name',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        for (final row in tables[name]!)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              row['is_judge_change'] == true
                                  ? 'Judge change: ${row['judge_name'] ?? 'Unassigned'}'
                                  : '${row['breed_id']}${row['variety_key'] == null ? '' : ' · ${row['variety_key']}'}',
                            ),
                            subtitle: Text(
                              '${_showName(row['show_id'])}\n${_sectionName(row)} · Order ${row['sort_order'] ?? 0} · ${_status(row['status'])}${row['judge_name'] == null ? '' : '\nJudge: ${row['judge_name']}'}',
                            ),
                            trailing:
                                row['is_judge_change'] == true ||
                                    AppSession.isSupportMode ||
                                    _error != null
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Edit table, order and progress',
                                    onPressed: () => _edit(row),
                                  ),
                          ),
                      ],
                    ),
                  ),
                if (tables.isEmpty)
                  _card(
                    const Text(
                      'No assignments yet. Open the shared Judging Line-Up above to add judges and breeds.',
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _countRow(String label, Map<String, int> counts) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label — ${counts.values.fold<int>(0, (a, b) => a + b)} total',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final show in widget.shows)
                SizedBox(
                  width: constraints.maxWidth >= 650
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(show['name'].toString()),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final section in (_sections ?? []).where(
                            (s) => s['show_id'] == show['id'],
                          ))
                            Chip(
                              label: Text(
                                '${section['display_name'] ?? section['letter']}: ${counts['${show['id']}/${section['id']}'] ?? 0}',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
      ],
    ),
  );
}
