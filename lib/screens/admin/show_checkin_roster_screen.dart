import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShowCheckinRosterScreen extends StatefulWidget {
  const ShowCheckinRosterScreen({super.key, required this.showId});

  final String showId;

  @override
  State<ShowCheckinRosterScreen> createState() =>
      _ShowCheckinRosterScreenState();
}

class _ShowCheckinRosterScreenState extends State<ShowCheckinRosterScreen> {
  final _db = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  String _status = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _db.rpc(
        'get_show_checkin_roster',
        params: {
          'p_show_id': widget.showId,
          'p_search': _search.text.trim(),
          'p_status': _status,
        },
      );
      if (!mounted) return;
      setState(() => _rows = List<Map<String, dynamic>>.from(result as List));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not load the check-in roster.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Check-In Roster'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  labelText: 'Search exhibitor name or number',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Check-in status'),
                items:
                    const [
                          ('all', 'All exhibitors'),
                          ('not_started', 'Not started'),
                          ('in_progress', 'In progress'),
                          ('completed', 'Completed'),
                          ('reviewed_by_secretary', 'Reviewed'),
                          ('locked', 'Locked'),
                        ]
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.$1,
                            child: Text(item.$2),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _status = value);
                  _load();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(
                                child: Text('No exhibitors match this filter.'),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _rows.length,
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final status =
                                row['checkin_status']?.toString() ??
                                'not_started';
                            return ListTile(
                              leading: Icon(_icon(status)),
                              title: Text(
                                (row['exhibitor_name'] ?? 'Exhibitor')
                                    .toString(),
                              ),
                              subtitle: Text(
                                '#${row['exhibitor_number'] ?? '—'}',
                              ),
                              trailing: Text(_label(status)),
                            );
                          },
                        ),
                ),
        ),
      ],
    ),
  );

  IconData _icon(String status) => switch (status) {
    'completed' => Icons.check_circle_outline,
    'reviewed_by_secretary' => Icons.fact_check_outlined,
    'locked' => Icons.lock_outline,
    'in_progress' => Icons.pending_outlined,
    _ => Icons.schedule_outlined,
  };

  String _label(String status) => switch (status) {
    'reviewed_by_secretary' => 'Reviewed',
    _ => status.replaceAll('_', ' '),
  };
}
