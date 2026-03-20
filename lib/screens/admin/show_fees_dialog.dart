// lib/screens/admin/show_fees_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowFeesDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShowFeesDialog(
        showId: showId,
        showName: showName,
      ),
    );
  }
}

class _ShowFeesDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowFeesDialog({
    required this.showId,
    required this.showName,
  });

  @override
  State<_ShowFeesDialog> createState() => _ShowFeesDialogState();
}

class _ShowFeesDialogState extends State<_ShowFeesDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  final _feePerEntry = TextEditingController();
  final _feePerShow = TextEditingController();

  bool _discountEnabled = false;
  String _discountType = 'amount';
  final _discountValue = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feePerEntry.dispose();
    _feePerShow.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final data = await supabase
          .from('show_fee_settings')
          .select(
              'fee_per_entry,fee_per_show,multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value')
          .eq('show_id', widget.showId)
          .maybeSingle();

      if (data == null) {
        _feePerEntry.text = '0';
        _feePerShow.text = '';
        _discountEnabled = false;
        _discountType = 'amount';
        _discountValue.text = '0';
      } else {
        _feePerEntry.text = (data['fee_per_entry'] ?? 0).toString();
        _feePerShow.text = (data['fee_per_show'] ?? '').toString();
        _discountEnabled = data['multi_show_discount_enabled'] == true;
        _discountType =
            (data['multi_show_discount_type'] ?? 'amount').toString();
        _discountValue.text =
            (data['multi_show_discount_value'] ?? 0).toString();
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _msg = 'Load failed: $e';
      });
    }
  }

  double? _parseMoney(String s) {
    final x = double.tryParse(s.trim());
    if (x == null || x < 0) return null;
    return x;
  }

  bool _validate() {
    final perEntry = _parseMoney(_feePerEntry.text);
    if (perEntry == null) {
      setState(() => _msg = 'Fee per entry must be ≥ 0.');
      return false;
    }

    if (_feePerShow.text.trim().isNotEmpty) {
      final perShow = _parseMoney(_feePerShow.text);
      if (perShow == null) {
        setState(() => _msg = 'Fee per show must be ≥ 0 or blank.');
        return false;
      }
    }

    final disc = _parseMoney(_discountValue.text);
    if (disc == null) {
      setState(() => _msg = 'Discount must be ≥ 0.');
      return false;
    }

    if (_discountType == 'percent' && disc > 100) {
      setState(() => _msg = 'Percent cannot exceed 100.');
      return false;
    }

    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await supabase.from('show_fee_settings').upsert({
        'show_id': widget.showId,
        'fee_per_entry': double.parse(_feePerEntry.text.trim()),
        'fee_per_show': _feePerShow.text.trim().isEmpty
            ? null
            : double.parse(_feePerShow.text.trim()),
        'multi_show_discount_enabled': _discountEnabled,
        'multi_show_discount_type': _discountType,
        'multi_show_discount_value':
            double.parse(_discountValue.text.trim()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Saved.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _msg = 'Save failed: $e';
      });
    }
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final success = _msg == 'Saved.';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 600,
          maxHeight: 720,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF11285A),
              Color(0xFF0B1C43),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/ringmaster_show_logo.png',
                    height: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Fee Settings — ${widget.showName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F6FB),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            if (_msg != null)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: success
                                      ? Colors.green.withOpacity(.08)
                                      : Colors.red.withOpacity(.08),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _msg!,
                                  style: TextStyle(
                                    color: success
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),

                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _section('Entry Fees', [
                                      TextField(
                                        controller: _feePerEntry,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Fee per animal / entry',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _feePerShow,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Optional: Fee per show',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ]),

                                    _section('Discounts', [
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                            'Enable multi-show discount'),
                                        value: _discountEnabled,
                                        onChanged: _saving
                                            ? null
                                            : (v) => setState(
                                                () =>
                                                    _discountEnabled = v),
                                      ),
                                      if (_discountEnabled) ...[
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          value: _discountType,
                                          items: const [
                                            DropdownMenuItem(
                                                value: 'amount',
                                                child: Text(
                                                    'Amount (\$ off)')),
                                            DropdownMenuItem(
                                                value: 'percent',
                                                child: Text(
                                                    'Percent (% off)')),
                                          ],
                                          onChanged: (v) => setState(
                                              () => _discountType =
                                                  v ?? 'amount'),
                                          decoration:
                                              const InputDecoration(
                                            labelText: 'Discount type',
                                            border:
                                                OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _discountValue,
                                          decoration:
                                              const InputDecoration(
                                            labelText: 'Discount value',
                                            border:
                                                OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    ]),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFFD4A623),
                                      padding:
                                          const EdgeInsets.symmetric(
                                              vertical: 16),
                                    ),
                                    onPressed:
                                        _saving ? null : _save,
                                    child: Text(
                                        _saving ? 'Saving…' : 'Save'),
                                  ),
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
    );
  }
}