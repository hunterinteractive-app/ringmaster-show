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
