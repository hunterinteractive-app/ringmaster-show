import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShowCheckinActivityScreen extends StatefulWidget {
  const ShowCheckinActivityScreen({super.key, required this.showId});

  final String showId;

  @override
  State<ShowCheckinActivityScreen> createState() =>
      _ShowCheckinActivityScreenState();
}

class _ShowCheckinActivityScreenState extends State<ShowCheckinActivityScreen> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _events = const [];
  bool _loading = true;
  String? _error;

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
      final result = await _db
          .from('show_checkin_audit_events')
          .select(
            'id,event_type,actor_type,details,created_at,exhibitors(display_name,first_name,last_name,exhibitor_number)',
          )
          .eq('show_id', widget.showId)
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() => _events = List<Map<String, dynamic>>.from(result));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'We could not load check-in activity.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Check-In Activity'),
      actions: [
        IconButton(
          tooltip: 'Refresh check-in activity',
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
            child: _events.isEmpty
                ? ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No check-in activity yet.')),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            _icon(event['event_type']?.toString() ?? ''),
                          ),
                          title: Text(
                            _title(event['event_type']?.toString() ?? ''),
                          ),
                          subtitle: Text(_subtitle(event)),
                        ),
                      );
                    },
                  ),
          ),
  );

  String _title(String event) => switch (event) {
    'identity_verified' => 'Identity verified',
    'change_request_submitted' => 'Change request submitted',
    'manual_payment_recorded' => 'Manual payment recorded',
    'checkin_completed' => 'Check-in completed by exhibitor',
    'checkin_completed_by_secretary' => 'Check-in completed by secretary',
    'checkin_reviewed' => 'Check-in reviewed',
    'checkin_locked' => 'Check-in locked',
    'receipt_email_sent' => 'Confirmation email sent',
    'checkin_add_entry_cart_item_created' => 'Entry added to cart',
    _ => event.replaceAll('_', ' '),
  };

  IconData _icon(String event) => switch (event) {
    'identity_verified' => Icons.verified_user_outlined,
    'change_request_submitted' => Icons.edit_note_outlined,
    'manual_payment_recorded' => Icons.payments_outlined,
    'checkin_completed' ||
    'checkin_completed_by_secretary' => Icons.how_to_reg_outlined,
    'checkin_reviewed' => Icons.fact_check_outlined,
    'checkin_locked' => Icons.lock_outline,
    'receipt_email_sent' => Icons.mark_email_read_outlined,
    _ => Icons.history_outlined,
  };

  String _subtitle(Map<String, dynamic> event) {
    final exhibitor = _map(event['exhibitors']);
    final name = (exhibitor['display_name'] ?? '').toString().trim().isNotEmpty
        ? exhibitor['display_name'].toString().trim()
        : '${exhibitor['first_name'] ?? ''} ${exhibitor['last_name'] ?? ''}'
              .trim();
    final number = exhibitor['exhibitor_number']?.toString().trim();
    final details = _map(event['details']);
    final pieces = <String>[
      if (name.isNotEmpty) name,
      if (number != null && number.isNotEmpty) '#$number',
      _detailSummary(details),
      _date(event['created_at']?.toString()),
    ]..removeWhere((value) => value.isEmpty);
    return pieces.join(' • ');
  }

  String _detailSummary(Map<String, dynamic> details) {
    if (details['amount_cents'] is num) {
      final amount = (details['amount_cents'] as num).toDouble() / 100;
      return '\$${amount.toStringAsFixed(2)} ${details['method'] ?? ''}'.trim();
    }
    if (details['request_type'] != null) {
      return 'Request: ${details['request_type'].toString().replaceAll('_', ' ')}';
    }
    return '';
  }

  String _date(String? raw) {
    final value = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (value == null) return '';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year} $hour:$minute $suffix';
  }
}
