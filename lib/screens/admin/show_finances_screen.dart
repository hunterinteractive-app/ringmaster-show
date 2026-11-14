import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';
import '../../services/ringmaster_backend.dart';
import '../../services/show_finances_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_time_utils.dart';
import '../../widgets/ringmaster_page_shell.dart';
import 'closeout/models/base/report_request.dart';
import 'print_packs/print_reports_service.dart';
import 'print_packs/print_pack_pdf_helpers.dart';

class ShowFinancesScreen extends StatefulWidget {
  const ShowFinancesScreen({super.key, required this.showId, this.gateway});
  final String showId;
  final ShowFinanceGateway? gateway;
  @override
  State<ShowFinancesScreen> createState() => _ShowFinancesScreenState();
}

class _ShowFinancesScreenState extends State<ShowFinancesScreen> {
  late final _gateway = widget.gateway ?? ShowFinancesService(ringMasterClient);
  Map<String, dynamic>? _data;
  bool _loading = true, _exporting = false;
  String? _error;
  String _search = '', _filter = 'All';
  List<ShowFinanceRow> get _rows => [
    for (final row in (_data?['exhibitors'] as List? ?? []))
      ShowFinanceRow(Map<String, dynamic>.from(row as Map)),
  ]..sort(ShowFinanceRow.compare);
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
      final data = await _gateway.load(widget.showId);
      if (mounted) setState(() => _data = data);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load show finances. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _record(ShowFinanceRow row, {bool credit = false}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Theme(
        data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
        child: ShowFinanceRecordDialog(
          row: row,
          credit: credit,
          save: (values) => _gateway.record(widget.showId, row.id, values),
        ),
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            credit
                ? 'Credit recorded.'
                : 'Payment recorded. No money was charged.',
          ),
        ),
      );
      await _load();
    }
  }

  Future<void> _history(ShowFinanceRow row) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
        child: _FinanceHistoryDialog(
          row: row,
          load: () => _gateway.history(widget.showId, row.id),
        ),
      ),
    );
  }

  Future<void> _report(PrintReport report, bool print) async {
    setState(() => _exporting = true);
    try {
      final file = await PrintReportsService(ringMasterClient).build(
        report,
        ReportRequest(
          showId: widget.showId,
          showName: _data?['show_name'] as String?,
          reportName: report.reportName,
          finalizeRunId: '',
          sectionIds: List<String>.from(_data?['section_ids'] as List? ?? []),
        ),
      );
      final bytes = Uint8List.fromList(file.bytes);
      if (print) {
        await Printing.layoutPdf(
          name: file.fileName,
          onLayout: (_) async => bytes,
        );
      } else {
        await savePdfToUserChosenLocation(
          bytes: bytes,
          suggestedName: file.fileName,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not prepare the report. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _card(Widget child) => Card(
    color: AppColors.surface,
    child: AppTheme.surfaceTextScope(
      context,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final filtered = rows
        .where(
          (r) =>
              r.matches(_search) && (_filter == 'All' || r.status == _filter),
        )
        .toList();
    final summaries = showFinanceSummaries(_data);
    return RingMasterPageShell(
      title: 'Show Finances',
      showId: widget.showId,
      subtitle: _data?['show_name'] as String? ?? '',
      showBackButton: true,
      showHomeButton: true,
      useScrollView: false,
      actions: [
        if (_data != null && !_loading && _error == null)
          PopupMenuButton<String>(
            tooltip: 'Financial reports',
            enabled: !_exporting,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.print),
            onSelected: (value) => _report(
              value.startsWith('paid') ? PrintReport.paid : PrintReport.unpaid,
              value.endsWith('print'),
            ),
            itemBuilder: (_) => [
              if (rows.any(
                (r) => r.received - r.cents('refunded_cents') > 0,
              )) ...[
                const PopupMenuItem(
                  value: 'paid-download',
                  child: Text('Download Paid Exhibitor Report'),
                ),
                const PopupMenuItem(
                  value: 'paid-print',
                  child: Text('Print Paid Exhibitor Report'),
                ),
              ],
              if (rows.any((r) => r.due > 0)) ...[
                const PopupMenuItem(
                  value: 'unpaid-download',
                  child: Text('Download Unpaid Balances'),
                ),
                const PopupMenuItem(
                  value: 'unpaid-print',
                  child: Text('Print Unpaid Balances'),
                ),
              ],
            ],
          ),
        IconButton(
          tooltip: 'Refresh finances',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: _card(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                for (final summary in summaries)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show totals · ${summary['currency'].toString().toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 24,
                            runSpacing: 12,
                            children: [
                              for (final metric in {
                                'Charged for show': 'charges_cents',
                                'Online fees charged': 'online_fee_cents',
                                'Refunded': 'refunded_cents',
                                'Outstanding': 'due_cents',
                                'Discounts': 'discount_cents',
                                'Club earned (estimate)': 'club_earned_cents',
                              }.entries)
                                SizedBox(
                                  width: constraints.maxWidth < 500
                                      ? (constraints.maxWidth - 24) / 2
                                      : 170,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        metric.key,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                        ),
                                      ),
                                      Text(
                                        summary[metric.value] == null
                                            ? 'Unavailable'
                                            : financeMoney(
                                                financeCents(
                                                  summary[metric.value],
                                                ),
                                                summary['currency'] as String,
                                              ),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Show charges are after discounts and credits, excluding online payment fees. Discounts shows applied entry discounts, excluding manual credits. Refunded includes refunded online fees.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          summary['club_earned_cents'] == null
                              ? 'Club earnings are unavailable because some payment or fee details are missing.'
                              : 'Club earned estimates money collected online and externally, less refunds and payment fees. It excludes unpaid balances and is before paybacks, show expenses, and any fees on external payments.',
                        ),
                      ],
                    ),
                  ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Record payments you have already received. Credits reduce a charge; they do not record money received. Unsubmitted carts are not included.',
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search exhibitors',
                          hintText: 'Name, number, email or phone',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final status in [
                            'All',
                            'Unpaid',
                            'Partial',
                            'Paid',
                          ])
                            ChoiceChip(
                              label: Text(status),
                              selected: _filter == status,
                              onSelected: (_) =>
                                  setState(() => _filter = status),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (filtered.isEmpty)
                  _card(
                    Text(
                      rows.isEmpty
                          ? 'No submitted-entry balances yet.'
                          : 'No exhibitors match these filters.',
                    ),
                  ),
                for (final row in filtered)
                  _card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.name,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${row.status} · ${row.cents('entry_count')} entries · ${row.cents('fur_count')} fur',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Charges: ${financeMoney(row.cents('charges_cents'), row.currency)}',
                        ),
                        Text(
                          'Received: ${financeMoney(row.received, row.currency)} · Refunded: ${financeMoney(row.cents('refunded_cents'), row.currency)}',
                        ),
                        if (row.cents('credit_cents') > 0)
                          Text(
                            'Credits applied: ${financeMoney(row.cents('credit_cents'), row.currency)}',
                          ),
                        Text(
                          'Balance due: ${financeMoney(row.due, row.currency)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (row.due > 0)
                              FilledButton.icon(
                                onPressed: () => _record(row),
                                icon: const Icon(Icons.add_card),
                                label: const Text('Record payment'),
                              ),
                            OutlinedButton(
                              onPressed: () => _history(row),
                              child: const Text('Payment history'),
                            ),
                            if (row.due > 0)
                              TextButton(
                                onPressed: () => _record(row, credit: true),
                                child: const Text('Apply credit'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class ShowFinanceRecordDialog extends StatefulWidget {
  const ShowFinanceRecordDialog({
    super.key,
    required this.row,
    required this.credit,
    required this.save,
  });
  final ShowFinanceRow row;
  final bool credit;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<ShowFinanceRecordDialog> createState() =>
      _ShowFinanceRecordDialogState();
}

class _ShowFinanceRecordDialogState extends State<ShowFinanceRecordDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _reference = TextEditingController();
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _submitted;
  @override
  void initState() {
    super.initState();
    _amount.text = (widget.row.due / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _submitted ??= {
      'credit': widget.credit,
      'p_request_id': const Uuid().v4(),
      'p_amount_cents': parseFinanceAmount(_amount.text),
      if (widget.credit)
        'p_reason': _reference.text.trim()
      else ...{
        'p_method': _method,
        'p_paid_at': _date.toUtc().toIso8601String(),
        'p_reference': _reference.text.trim(),
      },
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_submitted!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not confirm this record. Retry uses the same request and will not duplicate it. If the balance changed, close and refresh before recording again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.credit ? 'Apply credit' : 'Record payment received'),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.row.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Balance due: ${financeMoney(widget.row.due, widget.row.currency)}',
                ),
                const SizedBox(height: 12),
                Text(
                  widget.credit
                      ? 'This reduces the amount owed. It does not record a payment or issue a refund.'
                      : 'Use this only for money the club already received. It will not charge the exhibitor or send an email.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amount,
                  enabled: !_saving && _submitted == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount (${widget.row.currency.toUpperCase()})',
                  ),
                  validator: (value) {
                    final cents = parseFinanceAmount(value ?? '');
                    return cents == null
                        ? 'Enter an amount greater than zero, with up to 2 decimal places.'
                        : cents > widget.row.due
                        ? 'Amount cannot exceed the balance due.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                if (!widget.credit) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items: [
                      for (final method in {
                        'cash': 'Cash',
                        'check': 'Check',
                        'paypal': 'PayPal',
                        'venmo': 'Venmo',
                        'zelle': 'Zelle',
                        'other': 'Other',
                      }.entries)
                        DropdownMenuItem(
                          value: method.key,
                          child: Text(method.value),
                        ),
                    ],
                    onChanged: _saving || _submitted != null
                        ? null
                        : (value) => setState(() => _method = value!),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      'Received: ${_date.month}/${_date.day}/${_date.year}',
                    ),
                    onPressed: _saving || _submitted != null
                        ? null
                        : () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now(),
                              builder: (context, child) => Theme(
                                data: AppTheme.surfaceDialogTheme(
                                  Theme.of(context),
                                ),
                                child: child!,
                              ),
                            );
                            if (date != null && mounted) {
                              setState(() => _date = date);
                            }
                          },
                  ),
                ],
                TextFormField(
                  controller: _reference,
                  enabled: !_saving && _submitted == null,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: widget.credit
                        ? 'Reason for credit'
                        : 'Reference or note (optional)',
                  ),
                  validator: (value) =>
                      widget.credit && (value?.trim().length ?? 0) < 5
                      ? 'Enter a reason of at least 5 characters.'
                      : null,
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Saving…'
                : _error != null
                ? 'Retry'
                : widget.credit
                ? 'Apply credit'
                : 'Record payment',
          ),
        ),
      ],
    ),
  );
}

class _FinanceHistoryDialog extends StatefulWidget {
  const _FinanceHistoryDialog({required this.row, required this.load});
  final ShowFinanceRow row;
  final Future<Map<String, dynamic>> Function() load;
  @override
  State<_FinanceHistoryDialog> createState() => _FinanceHistoryDialogState();
}

class _FinanceHistoryDialogState extends State<_FinanceHistoryDialog> {
  late Future<Map<String, dynamic>> _future = widget.load();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Payment history · ${widget.row.name}'),
    content: SizedBox(
      width: 580,
      height: math.min(500, MediaQuery.sizeOf(context).height * .55),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                const Text('Could not load payment history.'),
                TextButton(
                  onPressed: () => setState(() {
                    _future = widget.load();
                  }),
                  child: const Text('Try again'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final payments = data['payments'] as List? ?? [],
              allocations = data['allocations'] as List? ?? [],
              events = data['events'] as List? ?? [];
          return ListView(
            children: [
              const Text(
                'Original receipts may cover more than one exhibitor. Only the allocated portion counts toward this exhibitor’s balance.',
              ),
              const Text('Times are shown in your local time zone.'),
              for (final a in allocations)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Checkout allocated here: ${financeMoney(financeCents(a['paid_online_cents']) + financeCents(a['paid_manual_cents']) - financeCents(a['refunded_cents']), widget.row.currency)}',
                  ),
                ),
              for (final p in payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Original receipt: ${financeMoney(financeCents(p['amount_cents']), p['currency'] as String? ?? widget.row.currency)}',
                  ),
                  subtitle: Text(
                    '${p['payer_name'] ?? ''}\n${p['method'] ?? ''} · ${p['status']}\n${formatLocalDateTime((p['paid_at'] ?? p['created_at'])?.toString())}\n${p['reference'] ?? ''}',
                  ),
                ),
              for (final e in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    e['kind'] == 'credit'
                        ? 'Credit: ${financeMoney(financeCents(e['amount_cents']), widget.row.currency)}'
                        : e['kind'] == 'allocation'
                        ? 'Balance allocation updated'
                        : 'External payment recorded',
                  ),
                  subtitle: Text(
                    '${e['reason'] ?? ''}\n${formatLocalDateTime(e['created_at']?.toString())}',
                  ),
                ),
              if (payments.isEmpty && events.isEmpty && allocations.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No recorded payments or adjustments.'),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
