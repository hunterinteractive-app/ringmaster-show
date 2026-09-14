import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/entry_refund_service.dart';
import '../../theme/app_theme.dart';

Widget _refundSurface(BuildContext context, Widget child) {
  final theme = AppTheme.surfaceTheme(Theme.of(context));
  return Theme(
    data: theme.copyWith(
      dialogTheme: theme.dialogTheme.copyWith(
        backgroundColor: AppColors.surface,
        titleTextStyle: theme.textTheme.headlineSmall?.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.text,
        ),
      ),
    ),
    child: child,
  );
}

class EntryRefundDialog extends StatefulWidget {
  const EntryRefundDialog({
    super.key,
    required this.showId,
    required this.exhibitorId,
    required this.exhibitorName,
    this.initialEntryId,
    this.service,
  });
  final String showId, exhibitorId, exhibitorName;
  final String? initialEntryId;
  final EntryRefundService? service;
  @override
  State<EntryRefundDialog> createState() => _EntryRefundDialogState();
}

class _EntryRefundDialogState extends State<EntryRefundDialog> {
  late final _service = widget.service ?? EntryRefundService();
  final _amount = TextEditingController();
  final _onlineAmount = TextEditingController(text: '0.00');
  final _reason = TextEditingController();
  final _selected = <String>{};
  Map<String, dynamic>? _data;
  String? _paymentId, _error, _notice;
  bool _busy = true,
      _includeOnline = false,
      _manualReturned = false,
      _changed = false;
  // Keep the exact payload and id after an uncertain response. Retrying may
  // complete the existing refund, but must never create a second transaction.
  Map<String, dynamic>? _submitted;

  List<Map<String, dynamic>> _rows(Object? value) => (value as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Map<String, dynamic>> get _payments => _rows(_data?['payments']);
  Map<String, dynamic>? get _payment =>
      _payments.where((p) => p['id'] == _paymentId).firstOrNull;
  bool get _manual => _payment?['manual'] == true;
  String get _currency => _payment?['currency']?.toString() ?? 'USD';
  bool get _available => _data?['enabled'] == true && _data?['locked'] != true;
  int _number(Object? value) => (value as num?)?.toInt() ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _onlineAmount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _service.options(widget.showId, widget.exhibitorId);
      if (!mounted) return;
      setState(() {
        _data = data;
        if (_payment == null && _payments.isNotEmpty) {
          _paymentId = _payments
              .firstWhere(
                (p) => _rows(
                  p['entries'],
                ).any((e) => e['id'] == widget.initialEntryId),
                orElse: () => _payments.first,
              )['id']
              .toString();
          if (widget.initialEntryId != null) {
            _selected.add(widget.initialEntryId!);
          }
          _suggestAmount();
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _suggestAmount() {
    final eligible = _rows(_payment?['entries']);
    _selected.removeWhere((id) => !eligible.any((e) => e['id'] == id));
    final suggested = eligible
        .where((e) => _selected.contains(e['id']))
        .fold<int>(0, (total, e) => total + _number(e['suggested_cents']));
    final remaining = _number(_payment?['remaining_entry_cents']);
    _amount.text = (suggested.clamp(0, remaining) / 100).toStringAsFixed(2);
    _suggestOnline();
    _manualReturned = false;
  }

  void _suggestOnline() {
    final base = refundAmountCents(_amount.text) ?? 0;
    final remaining = _number(_payment?['remaining_entry_cents']);
    final fees = _number(_payment?['remaining_online_fee_cents']);
    final suggested = remaining > 0
        ? (fees * base / remaining).floor().clamp(0, fees)
        : 0;
    _onlineAmount.text = (_includeOnline ? suggested / 100 : 0).toStringAsFixed(
      2,
    );
  }

  Future<void> _refund() async {
    final amount = refundAmountCents(_amount.text);
    final online = _includeOnline ? refundAmountCents(_onlineAmount.text) : 0;
    if (_selected.isEmpty ||
        _payment == null ||
        amount == null ||
        amount <= 0 ||
        amount > _number(_payment?['remaining_entry_cents']) ||
        online == null ||
        online < 0 ||
        online > _number(_payment?['remaining_online_fee_cents']) ||
        _reason.text.trim().length < 3 ||
        (_manual && !_manualReturned)) {
      setState(
        () => _error =
            'Select entries, enter an amount within the remaining payment, and provide a reason.${_manual ? ' Confirm the money has been returned.' : ''}',
      );
      return;
    }
    final selectedLabels = _rows(_data?['entries'])
        .where((e) => _selected.contains(e['id']))
        .map(
          (e) =>
              '${e['section']} · ${e['tattoo']} · ${e['breed']}${e['is_fur'] == true ? ' (Fur/Wool)' : ''}',
        );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _refundSurface(
        ctx,
        AlertDialog(
          title: Text(
            _manual
                ? 'Record Refund & Remove Entries?'
                : 'Refund & Remove Entries?',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Text(
                '${widget.exhibitorName}\n\n${selectedLabels.join('\n')}\n\n'
                'Entry refund: ${refundMoney(amount, _currency)}\n'
                'Online fee refund: ${refundMoney(online, _currency)}\n'
                'Total: ${refundMoney(amount + online, _currency)}\n\n'
                '${_manual ? 'This records the money you have already returned outside RingMaster.' : 'The money will be returned to the original payment method. Entries are removed after the refund succeeds.'}\n\n'
                'Only the selected show entries are removed. Saved animal profiles are kept.',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                _manual ? 'Record Refund & Remove' : 'Issue Refund & Remove',
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _submitted = {
      'action': 'refund',
      'request_id': const Uuid().v4(),
      'payment_id': _paymentId,
      'entry_ids': _selected.toList()..sort(),
      'entry_amount_cents': amount,
      'online_fee_cents': online,
      'reason': _reason.text.trim(),
      'manual_returned': _manualReturned,
    };
    await _send(_submitted!);
  }

  Future<void> _send(Map<String, dynamic> body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.submit(body);
      if (!mounted) return;
      setState(() {
        _changed = true;
        _notice = refundStatusMessage(result['status'].toString());
        _submitted = null;
        _selected.clear();
        _amount.clear();
      });
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '$error\nCheck the existing refund before starting another.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _rows(_payment?['entries']).map((e) => e['id']).toSet();
    final entries = _rows(
      _data?['entries'],
    ).where((e) => eligible.contains(e['id'])).toList();
    return _refundSurface(
      context,
      PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text('Refund & Remove Entries — ${widget.exhibitorName}'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_notice!),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_data != null && !_available)
                    Text(
                      _data?['locked'] == true
                          ? 'Unlock the show before refunding and removing entries.'
                          : 'Refunds are disabled in Show Fees and Payments.',
                    ),
                  if (_payments.isEmpty && !_busy)
                    const Text(
                      'No refundable payments were found for this exhibitor.',
                    ),
                  if (_payments.isNotEmpty) ...[
                    const Text(
                      'Select the original payment and the entries to remove. Review the amounts before confirming.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Payment to refund',
                      ),
                      items: _payments
                          .map(
                            (p) => DropdownMenuItem(
                              value: p['id'].toString(),
                              child: Text(
                                '${p['provider'].toString().toUpperCase()} · ${p['paid_at'].toString().split('T').first} · ${refundMoney(_number(p['remaining_entry_cents']), p['currency'].toString())} available',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _busy || _submitted != null
                          ? null
                          : (id) => setState(() {
                              _paymentId = id;
                              _selected.clear();
                              _includeOnline = false;
                              _suggestAmount();
                            }),
                    ),
                    if (entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No remaining entries match this payment.'),
                      ),
                    ...entries.map(
                      (e) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${e['section']} · ${e['tattoo']} · ${e['breed']}${e['is_fur'] == true ? ' (Fur/Wool)' : ''}',
                        ),
                        value: _selected.contains(e['id']),
                        onChanged: !_available || _busy || _submitted != null
                            ? null
                            : (checked) => setState(() {
                                if (checked == true) {
                                  _selected.add(e['id'].toString());
                                } else {
                                  _selected.remove(e['id']);
                                }
                                _suggestAmount();
                              }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amount,
                      enabled: _available && !_busy && _submitted == null,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Entry refund amount ($_currency)',
                        helperText:
                            'Suggested from the saved fees. Adjust for the selected entries as needed.',
                      ),
                      onChanged: (_) => setState(() {
                        _suggestOnline();
                        _manualReturned = false;
                      }),
                    ),
                    if (!_manual &&
                        _number(_payment?['remaining_online_fee_cents']) >
                            0) ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include online fees'),
                        value: _includeOnline,
                        onChanged: !_available || _busy || _submitted != null
                            ? null
                            : (v) => setState(() {
                                _includeOnline = v == true;
                                _suggestOnline();
                              }),
                      ),
                      if (_includeOnline)
                        TextField(
                          controller: _onlineAmount,
                          enabled: !_busy && _submitted == null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Online fee refund ($_currency)',
                            helperText:
                                'Up to ${refundMoney(_number(_payment?['remaining_online_fee_cents']), _currency)}',
                          ),
                        ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reason,
                      enabled: _available && !_busy && _submitted == null,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Reason for refund',
                      ),
                    ),
                    if (_manual)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I have returned this money to the exhibitor outside RingMaster.',
                        ),
                        subtitle: Text(
                          'Original payment: ${_payment?['method']}. This records a refund; it does not send money.',
                        ),
                        value: _manualReturned,
                        onChanged: !_available || _busy || _submitted != null
                            ? null
                            : (v) =>
                                  setState(() => _manualReturned = v == true),
                      ),
                  ],
                  if (_rows(_data?['history']).isNotEmpty) ...[
                    const Divider(height: 32),
                    const Text(
                      'Refund History',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._rows(_data?['history']).map(
                      (r) => _refundHistoryTile(
                        r,
                        _busy
                            ? null
                            : () => _send({
                                'action': 'status',
                                'request_id': r['id'],
                              }),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, _changed),
              child: const Text('Close'),
            ),
            if (_submitted != null)
              FilledButton(
                onPressed: _busy ? null : () => _send(_submitted!),
                child: const Text('Check / Retry Existing Refund'),
              )
            else
              FilledButton(
                onPressed: _busy || !_available || _selected.isEmpty
                    ? null
                    : _refund,
                child: const Text('Review Refund'),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _refundHistoryTile(Map<String, dynamic> r, VoidCallback? onCheck) {
  final status = r['status'].toString();
  return ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      '${r['exhibitor_name'] == null ? '' : '${r['exhibitor_name']} · '}${refundMoney((r['amount_cents'] as num).toInt(), r['currency'].toString())} · ${status.replaceAll('_', ' ')}',
    ),
    subtitle: Text(
      '${r['entry_count']} entries · ${r['reason']}\n${r['error'] ?? refundStatusMessage(status)}',
    ),
    trailing: ['succeeded', 'failed'].contains(status)
        ? null
        : TextButton(onPressed: onCheck, child: const Text('Check Status')),
  );
}

class EntryRefundHistoryDialog extends StatefulWidget {
  const EntryRefundHistoryDialog({super.key, required this.showId});
  final String showId;
  @override
  State<EntryRefundHistoryDialog> createState() =>
      _EntryRefundHistoryDialogState();
}

class _EntryRefundHistoryDialogState extends State<EntryRefundHistoryDialog> {
  final _service = EntryRefundService();
  List<Map<String, dynamic>> _history = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? requestId]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (requestId != null) {
        await _service.submit({'action': 'status', 'request_id': requestId});
      }
      final history = await _service.history(widget.showId);
      if (mounted) setState(() => _history = history);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _refundSurface(
    context,
    AlertDialog(
      title: const Text('Refund History'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if (!_busy && _history.isEmpty)
                const Text(
                  'No entry refunds have been recorded for this show.',
                ),
              ..._history.map(
                (r) => _refundHistoryTile(
                  r,
                  _busy ? null : () => _load(r['id'].toString()),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _load(),
          child: const Text('Refresh'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
