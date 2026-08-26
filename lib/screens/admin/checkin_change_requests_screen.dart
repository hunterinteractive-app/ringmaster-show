import 'package:flutter/material.dart';
import 'package:ringmaster_show/widgets/accessible_icon_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CheckinChangeRequestsScreen extends StatefulWidget {
  const CheckinChangeRequestsScreen({super.key, required this.showId});
  final String showId;
  @override
  State<CheckinChangeRequestsScreen> createState() => _State();
}

class _State extends State<CheckinChangeRequestsScreen> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String filter = 'pending';
  String? error;
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await db
          .from('show_checkin_change_requests')
          .select(
            'id,exhibitor_id,status,request_type,requested_changes,original_values,applied_changes,exhibitor_note,review_note,created_at,exhibitors(display_name,showing_name),entries(tattoo,breed,variety)',
          )
          .eq('show_id', widget.showId)
          .order('created_at');
      if (mounted) setState(() => rows = List<Map<String, dynamic>>.from(r));
    } catch (_) {
      if (mounted) setState(() => error = 'We could not load change requests.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> review(Map<String, dynamic> row, bool ok) async {
    final note = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ok ? 'Approve change request' : 'Deny change request'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note for exhibitor (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ok ? 'Approve & Apply' : 'Deny Request'),
          ),
        ],
      ),
    );
    if (submitted != true) {
      note.dispose();
      return;
    }
    await db.rpc(
      'review_checkin_change_request',
      params: {
        'p_request_id': row['id'],
        'p_approved': ok,
        'p_review_note': note.text.trim(),
      },
    );
    note.dispose();
    await load();
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  String _changeSummary(Map<String, dynamic> row) {
    const labels = <String, String>{
      'ear_number': 'Tattoo / Ear #',
      'breed': 'Breed',
      'variety': 'Variety',
      'class': 'Class',
      'sex': 'Sex',
      'fur_variety': 'Fur Variety',
      'scratch_entry': 'Scratch entry',
    };
    final original = _map(row['original_values']);
    final requested = _map(row['requested_changes']);
    final applied = _map(row['applied_changes']);
    final lines = <String>[];
    if (row['request_type'] == 'add_entry') {
      const addLabels = <String, String>{
        'section_id': 'Show section',
        'ear_number': 'Tattoo / Ear #',
        'animal_name': 'Animal name',
        'breed': 'Breed',
        'variety': 'Variety',
        'class': 'Class',
        'sex': 'Sex',
        'fur_variety': 'Fur variety',
      };
      for (final entry in addLabels.entries) {
        if (requested.containsKey(entry.key)) {
          lines.add('${entry.value}: ${requested[entry.key]}');
        }
      }
      return lines.join('\n');
    }
    for (final key in labels.keys) {
      if (requested.containsKey(key)) {
        lines.add(
          '${labels[key]}: ${original[key] ?? '—'} → ${requested[key]}',
        );
      }
      if (applied.containsKey(key)) {
        lines.add(
          '${labels[key]}: ${original[key] ?? '—'} → ${applied[key]} (applied)',
        );
      }
    }
    return lines.join('\n');
  }

  bool _isPending(Map<String, dynamic> row) => const {
    'submitted',
    'pending_payment',
    'pending_review',
  }.contains(row['status']);

  List<Map<String, dynamic>> get _visibleRows => switch (filter) {
    'pending' => rows.where(_isPending).toList(),
    'approved' => rows.where((row) => row['status'] == 'approved').toList(),
    'denied' => rows.where((row) => row['status'] == 'denied').toList(),
    'cancelled' => rows.where((row) => row['status'] == 'cancelled').toList(),
    _ => rows,
  };

  int _countFor(String value) => switch (value) {
    'pending' => rows.where(_isPending).length,
    _ => rows.where((row) => row['status'] == value).length,
  };

  String _requestLabel(Map<String, dynamic> row) {
    final exhibitor = _map(row['exhibitors']);
    final name =
        (exhibitor['display_name'] ?? exhibitor['showing_name'] ?? 'Exhibitor')
            .toString();
    final type = (row['request_type'] ?? 'change').toString().replaceAll(
      '_',
      ' ',
    );
    return '$name • $type';
  }

  Future<void> recordPayment(Map<String, dynamic> row) async {
    final amount = TextEditingController();
    final reference = TextEditingController();
    String method = 'cash';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: r'$',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items:
                    const [
                          'cash',
                          'check',
                          'digital',
                          'stripe',
                          'square',
                          'paypal',
                        ]
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                onChanged: (value) => setDialogState(() => method = value!),
              ),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await db.rpc(
        'record_checkin_manual_payment',
        params: {
          'p_show_id': widget.showId,
          'p_exhibitor_id': row['exhibitor_id'],
          'p_amount_cents': ((double.tryParse(amount.text) ?? 0) * 100).round(),
          'p_method': method,
          'p_reference': reference.text.trim(),
          'p_receipt_preference': 'no_receipt',
        },
      );
      await load();
    }
    amount.dispose();
    reference.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Check-In Change Requests'),
      actions: [
        AccessibleIconButton(
          tooltip: 'Refresh change requests',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in const [
                    ('pending', 'Pending'),
                    ('approved', 'Approved'),
                    ('denied', 'Denied'),
                    ('cancelled', 'Cancelled'),
                    ('all', 'All'),
                  ])
                    ChoiceChip(
                      label: Text('${item.$2} (${_countFor(item.$1)})'),
                      selected: filter == item.$1,
                      onSelected: (_) => setState(() => filter = item.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_visibleRows.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No change requests match this filter.'),
                  ),
                ),
              for (final r in _visibleRows)
                Card(
                  child: ListTile(
                    title: Text(_requestLabel(r)),
                    subtitle: Text(
                      [
                        _changeSummary(r),
                        if ((r['exhibitor_note'] ?? '').toString().isNotEmpty)
                          'Exhibitor note: ${r['exhibitor_note']}',
                        if ((r['review_note'] ?? '').toString().isNotEmpty)
                          'Review note: ${r['review_note']}',
                      ].where((line) => line.isNotEmpty).join('\n'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AccessibleIconButton(
                          tooltip: 'Record payment',
                          onPressed: () => recordPayment(r),
                          icon: const Icon(Icons.payments_outlined),
                        ),
                        if (r['status'] == 'submitted' ||
                            r['status'] == 'pending_review')
                          AccessibleIconButton(
                            tooltip: 'Approve and apply request',
                            onPressed: () => review(r, true),
                            icon: const Icon(Icons.check),
                          ),
                        if (r['status'] == 'submitted' ||
                            r['status'] == 'pending_review')
                          AccessibleIconButton(
                            tooltip: 'Deny request',
                            onPressed: () => review(r, false),
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
  );
}
