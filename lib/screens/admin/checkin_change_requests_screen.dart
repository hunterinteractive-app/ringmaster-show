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
          'id,exhibitor_id,status,request_type,exhibitor_note,review_note,created_at,exhibitors(display_name,showing_name),entries(tattoo,breed,variety)',
        )
        .eq('show_id', widget.showId)
        .order('created_at');
    if (mounted)
      setState(
        () => {rows = List<Map<String, dynamic>>.from(r), loading = false},
      );
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> review(String id, bool ok) async {
    await db.rpc(
      'review_checkin_change_request',
      params: {'p_request_id': id, 'p_approved': ok},
    );
    await load();
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
                value: method,
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
                      '${r['exhibitor_note'] ?? ''}\n${r['entries'] ?? ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => recordPayment(r),
                          icon: const Icon(Icons.payments_outlined),
                        ),
                        if (r['status'] == 'submitted')
                          IconButton(
                            onPressed: () => review(r['id'], true),
                            icon: const Icon(Icons.check),
                          ),
                        if (r['status'] == 'submitted')
                          IconButton(
                            onPressed: () => review(r['id'], false),
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
