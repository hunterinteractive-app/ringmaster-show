import 'package:flutter/material.dart';
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
  Future<void> load() async {
    final r = await db
        .from('show_checkin_change_requests')
        .select(
          'id,exhibitor_id,status,request_type,requested_changes,original_values,applied_changes,exhibitor_note,review_note,created_at,exhibitors(display_name,showing_name),entries(tattoo,breed,variety)',
        )
        .eq('show_id', widget.showId)
        .order('created_at');
    if (mounted) {
      setState(() {
        rows = List<Map<String, dynamic>>.from(r);
        loading = false;
      });
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
    appBar: AppBar(title: const Text('Check-In Change Requests')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: [
              for (final r in rows)
                Card(
                  child: ListTile(
                    title: Text('${r['request_type']} • ${r['status']}'),
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
                        IconButton(
                          onPressed: () => recordPayment(r),
                          icon: const Icon(Icons.payments_outlined),
                        ),
                        if (r['status'] == 'submitted' ||
                            r['status'] == 'pending_review')
                          IconButton(
                            onPressed: () => review(r, true),
                            icon: const Icon(Icons.check),
                          ),
                        if (r['status'] == 'submitted' ||
                            r['status'] == 'pending_review')
                          IconButton(
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
