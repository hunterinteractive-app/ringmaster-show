import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'checkin_change_requests_screen.dart';
import 'show_checkin_activity_screen.dart';
import 'show_checkin_roster_screen.dart';

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

  Future<Map<String, dynamic>?> _pickExhibitor(String title) async {
    final search = TextEditingController();
    List<Map<String, dynamic>> results = const [];
    Map<String, dynamic>? selected;
    String? searchError;
    var hasLoaded = false;

    Future<void> loadResults(StateSetter setDialogState) async {
      try {
        final data = await _db.rpc(
          'search_show_checkin_exhibitors',
          params: {'p_show_id': widget.showId, 'p_search': search.text.trim()},
        );
        setDialogState(() {
          results = List<Map<String, dynamic>>.from(data as List);
          searchError = null;
        });
      } catch (_) {
        setDialogState(() => searchError = 'Could not search exhibitors.');
      }
    }

    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AppTheme.gradientTextScope(
        context,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            if (!hasLoaded) {
              hasLoaded = true;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => loadResults(setDialogState),
              );
            }
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppTheme.surfaceTextScope(
                      context,
                      child: TextField(
                        controller: search,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Exhibitor name or number',
                          suffixIcon: IconButton(
                            tooltip: 'Search exhibitors',
                            onPressed: () => loadResults(setDialogState),
                            icon: const Icon(Icons.search),
                          ),
                        ),
                        onSubmitted: (_) => loadResults(setDialogState),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 230,
                      child: ListView(
                        children: [
                          for (final exhibitor in results)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppTheme.surfaceTextScope(
                                context,
                                child: Card(
                                  child: ListTile(
                                    leading: Icon(
                                      selected?['exhibitor_id'] ==
                                              exhibitor['exhibitor_id']
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                    ),
                                    selected:
                                        selected?['exhibitor_id'] ==
                                        exhibitor['exhibitor_id'],
                                    onTap: () => setDialogState(
                                      () => selected = exhibitor,
                                    ),
                                    title: Text(
                                      (exhibitor['exhibitor_name'] ??
                                              'Exhibitor')
                                          .toString(),
                                    ),
                                    subtitle: Text(
                                      '#${exhibitor['exhibitor_number'] ?? '—'} • ${exhibitor['checkin_status'] ?? 'not checked in'}',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (searchError != null)
                            Text(
                              searchError!,
                              style: const TextStyle(color: AppColors.danger),
                            )
                          else if (results.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: Text('No exhibitors match this search.'),
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
            );
          },
        ),
      ),
    );
    search.dispose();
    return picked;
  }

  Future<void> _completeForExhibitor() async {
    final picked = await _pickExhibitor('Complete Check-In for Exhibitor');
    if (picked == null || !mounted) return;
    await _confirmSecretaryCheckin(picked);
  }

  Future<void> _recordPayment() async {
    final exhibitor = await _pickExhibitor('Record Payment');
    if (exhibitor == null || !mounted) return;
    try {
      final rawContext = await _db.rpc(
        'get_show_checkin_payment_context',
        params: {
          'p_show_id': widget.showId,
          'p_exhibitor_id': exhibitor['exhibitor_id'],
        },
      );
      final payment = Map<String, dynamic>.from(rawContext as Map);
      final dueCents = (payment['balance_due_cents'] as num?)?.toInt() ?? 0;
      if (dueCents <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This exhibitor does not have a balance due.'),
            ),
          );
        }
        return;
      }
      await _recordPaymentForExhibitor(exhibitor, dueCents);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load this exhibitor’s payment details.'),
          ),
        );
      }
    }
  }

  Future<void> _recordPaymentForExhibitor(
    Map<String, dynamic> exhibitor,
    int dueCents,
  ) async {
    final amount = TextEditingController(
      text: (dueCents / 100).toStringAsFixed(2),
    );
    final reference = TextEditingController();
    var method = 'cash';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Record Payment — ${exhibitor['exhibitor_name'] ?? 'Exhibitor'}',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Balance due: \$${(dueCents / 100).toStringAsFixed(2)}'),
                const SizedBox(height: 12),
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
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
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setDialogState(() => method = value ?? method),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference or check number (optional)',
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
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final amountCents = ((double.tryParse(amount.text.trim()) ?? 0) * 100)
          .round();
      if (amountCents <= 0 || amountCents > dueCents) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                r'Enter an amount greater than $0 and no more than the balance due.',
              ),
            ),
          );
        }
      } else {
        try {
          await _db.rpc(
            'record_checkin_manual_payment',
            params: {
              'p_show_id': widget.showId,
              'p_exhibitor_id': exhibitor['exhibitor_id'],
              'p_amount_cents': amountCents,
              'p_method': method,
              'p_reference': reference.text.trim(),
              'p_receipt_preference': 'no_receipt',
            },
          );
          await _load();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Payment recorded.')));
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not record this payment.')),
            );
          }
        }
      }
    }
    amount.dispose();
    reference.dispose();
  }

  Future<void> _confirmSecretaryCheckin(Map<String, dynamic> exhibitor) async {
    final initials = TextEditingController();
    final signature = TextEditingController();
    final note = TextEditingController();
    var entriesConfirmed = false;
    var receiptPreference = 'no_receipt';
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
                    style: TextStyle(
                      color: AppColors.headerForeground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  activeColor: AppColors.header,
                  checkColor: AppColors.headerForeground,
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: receiptPreference,
                  decoration: const InputDecoration(
                    labelText: 'Receipt preference',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'email_receipt',
                      child: Text('Email receipt confirmation'),
                    ),
                    DropdownMenuItem(
                      value: 'no_receipt',
                      child: Text('No receipt needed'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => receiptPreference = value ?? 'no_receipt',
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
        final result = await _db.rpc(
          'complete_exhibitor_checkin_by_secretary_with_receipt',
          params: {
            'p_show_id': widget.showId,
            'p_exhibitor_id': exhibitor['exhibitor_id'],
            'p_entries_confirmed': true,
            'p_initials': initials.text.trim(),
            'p_signature_data': signature.text.trim(),
            'p_note': note.text.trim(),
            'p_receipt_preference': receiptPreference,
          },
        );
        var message = 'Check-in completed by secretary.';
        if (receiptPreference == 'email_receipt') {
          final record = Map<String, dynamic>.from(result as Map);
          try {
            final receipt = await _db.functions.invoke(
              'checkin-send-receipt',
              body: {'checkin_record_id': record['id']},
            );
            message = receipt.status >= 200 && receipt.status < 300
                ? 'Check-in completed and confirmation email sent.'
                : 'Check-in completed. The confirmation email could not be sent.';
          } catch (_) {
            message =
                'Check-in completed. The confirmation email could not be sent.';
          }
        }
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _changeCheckinStatus(
    Map<String, dynamic> row,
    String status,
  ) async {
    final action = status == 'locked' ? 'lock' : 'mark as reviewed';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${action[0].toUpperCase()}${action.substring(1)} check-in?',
        ),
        content: Text(
          status == 'locked'
              ? 'This prevents any further changes through the exhibitor portal.'
              : 'This records that the secretary reviewed the completed check-in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(status == 'locked' ? 'Lock Check-In' : 'Mark Reviewed'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.rpc(
        'update_show_checkin_record_status',
        params: {'p_checkin_record_id': row['id'], 'p_status': status},
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'locked'
                  ? 'Check-in locked.'
                  : 'Check-in marked as reviewed.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this check-in.')),
        );
      }
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
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: _loading ? null : _completeForExhibitor,
              icon: const Icon(Icons.how_to_reg_outlined, size: 18),
              label: const Text('Complete Check-In'),
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: _loading ? null : _recordPayment,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Record Payment'),
              style: FilledButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppTheme.gradientTextScope(
        context,
        child: _loading
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: AppColors.headerForeground),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _metric(
                          context,
                          'Completed',
                          _count(records, 'completed'),
                          Icons.check_circle_outline,
                        ),
                        _metric(
                          context,
                          'In progress',
                          _count(records, 'in_progress'),
                          Icons.pending_outlined,
                        ),
                        _metric(
                          context,
                          'Not started',
                          _count(records, 'not_started'),
                          Icons.schedule_outlined,
                        ),
                        _metric(
                          context,
                          'Locked',
                          _count(records, 'locked'),
                          Icons.lock_outline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    AppTheme.surfaceTextScope(
                      context,
                      child: Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.people_outline),
                              title: const Text('Check-In Roster'),
                              subtitle: const Text(
                                'Search all entered exhibitors and see their check-in status',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ShowCheckinRosterScreen(
                                    showId: widget.showId,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.history_outlined),
                              title: const Text('Check-In Activity'),
                              subtitle: const Text(
                                'View verifications, payments, changes, and status updates',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ShowCheckinActivityScreen(
                                    showId: widget.showId,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(Icons.playlist_add_check),
                              title: const Text('Check-In Change Requests'),
                              subtitle: const Text(
                                'Review exhibitor corrections and requests',
                              ),
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
                              title: const Text(
                                'Exhibitors with a balance due',
                              ),
                              trailing: Chip(
                                label: Text(
                                  '${_data?['unpaid_exhibitors'] ?? 0}',
                                ),
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ShowCheckinRosterScreen(
                                    showId: widget.showId,
                                    initialStatus: 'balance_due',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Recent check-ins',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.headerForeground,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (recent.isEmpty)
                      AppTheme.surfaceTextScope(
                        context,
                        child: const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No exhibitors have checked in yet.'),
                          ),
                        ),
                      ),
                    for (final row in recent)
                      AppTheme.surfaceTextScope(
                        context,
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.verified_outlined),
                            title: Text(
                              (row['exhibitor_name'] ?? 'Exhibitor').toString(),
                            ),
                            subtitle: Text(_subtitle(row)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (row['receipt_preference'] ==
                                    'email_receipt')
                                  Icon(
                                    row['receipt_sent_at'] == null
                                        ? Icons.mail_outline
                                        : Icons.mark_email_read_outlined,
                                  ),
                                if (row['status'] != 'locked')
                                  PopupMenuButton<String>(
                                    onSelected: (value) =>
                                        _changeCheckinStatus(row, value),
                                    itemBuilder: (context) => [
                                      if (row['status'] == 'completed')
                                        const PopupMenuItem(
                                          value: 'reviewed_by_secretary',
                                          child: Text('Mark reviewed'),
                                        ),
                                      const PopupMenuItem(
                                        value: 'locked',
                                        child: Text('Lock check-in'),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    String label,
    int count,
    IconData icon,
  ) => SizedBox(
    width: 150,
    child: AppTheme.surfaceTextScope(
      context,
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
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(label),
            ],
          ),
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
