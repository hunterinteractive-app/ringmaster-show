import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'checkin_change_requests_screen.dart';

class ShowCheckinDashboardScreen extends StatefulWidget {
  const ShowCheckinDashboardScreen({super.key, required this.showId});

  final String showId;

  @override
  State<ShowCheckinDashboardScreen> createState() =>
      _ShowCheckinDashboardScreenState();
}

class _ShowCheckinDashboardScreenState
    extends State<ShowCheckinDashboardScreen> {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _db.rpc(
        'get_show_checkin_dashboard',
        params: {'p_show_id': widget.showId},
      );
      if (!mounted) return;
      setState(() => _data = Map<String, dynamic>.from(result as Map));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not load the check-in dashboard.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _completeForExhibitor() async {
    final search = TextEditingController();
    List<Map<String, dynamic>> results = const [];
    Map<String, dynamic>? selected;
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Complete Check-In for Exhibitor'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Exhibitor name or number',
                    suffixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) async {
                    final data = await _db.rpc(
                      'search_show_checkin_exhibitors',
                      params: {
                        'p_show_id': widget.showId,
                        'p_search': search.text.trim(),
                      },
                    );
                    setDialogState(() {
                      results = List<Map<String, dynamic>>.from(data as List);
                    });
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 230,
                  child: ListView(
                    children: [
                      for (final exhibitor in results)
                        ListTile(
                          leading: Icon(
                            selected?['exhibitor_id'] ==
                                    exhibitor['exhibitor_id']
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                          ),
                          selected:
                              selected?['exhibitor_id'] ==
                              exhibitor['exhibitor_id'],
                          onTap: () =>
                              setDialogState(() => selected = exhibitor),
                          title: Text(
                            (exhibitor['exhibitor_name'] ?? 'Exhibitor')
                                .toString(),
                          ),
                          subtitle: Text(
                            '#${exhibitor['exhibitor_number'] ?? '—'} • ${exhibitor['checkin_status'] ?? 'not checked in'}',
                          ),
                        ),
                      if (results.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Text('Search to find an exhibitor.'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    search.dispose();
    if (picked == null || !mounted) return;
    await _confirmSecretaryCheckin(picked);
  }

  Future<void> _confirmSecretaryCheckin(Map<String, dynamic> exhibitor) async {
    final initials = TextEditingController();
    final signature = TextEditingController();
    final note = TextEditingController();
    var entriesConfirmed = false;
    final complete = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Check In ${exhibitor['exhibitor_name'] ?? 'Exhibitor'}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  value: entriesConfirmed,
                  onChanged: (value) =>
                      setDialogState(() => entriesConfirmed = value ?? false),
                  title: const Text(
                    'I confirmed the exhibitor’s entries are correct.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                TextField(
                  controller: initials,
                  decoration: const InputDecoration(
                    labelText: 'Initials (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: signature,
                  decoration: const InputDecoration(
                    labelText: 'Signature (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Staff note (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: entriesConfirmed
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Complete Check-In'),
            ),
          ],
        ),
      ),
    );
    if (complete == true) {
      try {
        await _db.rpc(
          'complete_exhibitor_checkin_by_secretary',
          params: {
            'p_show_id': widget.showId,
            'p_exhibitor_id': exhibitor['exhibitor_id'],
            'p_entries_confirmed': true,
            'p_initials': initials.text.trim(),
            'p_signature_data': signature.text.trim(),
            'p_note': note.text.trim(),
          },
        );
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Check-in completed by secretary.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not complete this check-in.')),
          );
        }
      }
    }
    initials.dispose();
    signature.dispose();
    note.dispose();
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  int _count(Map<String, dynamic> records, String status) =>
      (records[status] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final records = _map(_data?['records']);
    final recent = List<Map<String, dynamic>>.from(
      (_data?['recent_checkins'] as List? ?? const []).whereType<Map>().map(
        Map<String, dynamic>.from,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-In Dashboard'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _completeForExhibitor,
            icon: const Icon(Icons.how_to_reg_outlined),
            tooltip: 'Complete Check-In for Exhibitor',
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Live check-in status',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metric(
                        'Completed',
                        _count(records, 'completed'),
                        Icons.check_circle_outline,
                      ),
                      _metric(
                        'In progress',
                        _count(records, 'in_progress'),
                        Icons.pending_outlined,
                      ),
                      _metric(
                        'Not started',
                        _count(records, 'not_started'),
                        Icons.schedule_outlined,
                      ),
                      _metric(
                        'Locked',
                        _count(records, 'locked'),
                        Icons.lock_outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.playlist_add_check),
                          title: const Text('Pending change requests'),
                          trailing: Chip(
                            label: Text(
                              '${_data?['pending_change_requests'] ?? 0}',
                            ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CheckinChangeRequestsScreen(
                                showId: widget.showId,
                              ),
                            ),
                          ).then((_) => _load()),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: const Text('Exhibitors with a balance due'),
                          trailing: Chip(
                            label: Text('${_data?['unpaid_exhibitors'] ?? 0}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Recent check-ins',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (recent.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No exhibitors have checked in yet.'),
                      ),
                    ),
                  for (final row in recent)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.verified_outlined),
                        title: Text(
                          (row['exhibitor_name'] ?? 'Exhibitor').toString(),
                        ),
                        subtitle: Text(_subtitle(row)),
                        trailing: row['receipt_preference'] == 'email_receipt'
                            ? Icon(
                                row['receipt_sent_at'] == null
                                    ? Icons.mail_outline
                                    : Icons.mark_email_read_outlined,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _metric(String label, int count, IconData icon) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 10),
            Text(
              '$count',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );

  String _subtitle(Map<String, dynamic> row) {
    final number = row['exhibitor_number']?.toString().trim();
    final status =
        row['status']?.toString().replaceAll('_', ' ') ?? 'completed';
    return [
      if (number != null && number.isNotEmpty) '#$number',
      status,
    ].join(' • ');
  }
}
