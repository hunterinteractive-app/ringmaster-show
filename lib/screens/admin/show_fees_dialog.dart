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
      builder: (_) => _ShowFeesDialog(showId: showId, showName: showName),
    );
  }
}

class _ShowFeesDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowFeesDialog({required this.showId, required this.showName});

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
  String _discountType = 'amount'; // amount|percent
  final _discountValue = TextEditingController();

  @override
  void dispose() {
    _feePerEntry.dispose();
    _feePerShow.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  String _fmtNum(String? s) => (s ?? '').trim();

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
        // defaults
        _feePerEntry.text = '0';
        _feePerShow.text = '';
        _discountEnabled = false;
        _discountType = 'amount';
        _discountValue.text = '0';
      } else {
        _feePerEntry.text = (data['fee_per_entry'] ?? 0).toString();
        _feePerShow.text = (data['fee_per_show'] ?? '').toString();
        _discountEnabled = data['multi_show_discount_enabled'] == true;
        _discountType = (data['multi_show_discount_type'] ?? 'amount').toString();
        _discountValue.text = (data['multi_show_discount_value'] ?? 0).toString();
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
    if (x == null) return null;
    if (x < 0) return null;
    return x;
  }

  bool _validate() {
    final perEntry = _parseMoney(_feePerEntry.text);
    if (perEntry == null) {
      setState(() => _msg = 'Fee per entry must be a valid number ≥ 0.');
      return false;
    }

    if (_feePerShow.text.trim().isNotEmpty) {
      final perShow = _parseMoney(_feePerShow.text);
      if (perShow == null) {
        setState(() => _msg = 'Fee per show must be a valid number ≥ 0 (or blank).');
        return false;
      }
    }

    final disc = _parseMoney(_discountValue.text);
    if (disc == null) {
      setState(() => _msg = 'Discount value must be a valid number ≥ 0.');
      return false;
    }

    if (_discountType == 'percent' && disc > 100) {
      setState(() => _msg = 'Percent discount cannot exceed 100%.');
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

    final feePerEntry = double.parse(_feePerEntry.text.trim());
    final feePerShow = _feePerShow.text.trim().isEmpty ? null : double.parse(_feePerShow.text.trim());
    final discVal = double.parse(_discountValue.text.trim());

    try {
      await supabase.from('show_fee_settings').upsert({
        'show_id': widget.showId,
        'fee_per_entry': feePerEntry,
        'fee_per_show': feePerShow,
        'multi_show_discount_enabled': _discountEnabled,
        'multi_show_discount_type': _discountType,
        'multi_show_discount_value': discVal,
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Fee Settings — ${widget.showName}'),
      content: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_msg != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _msg!,
                        style: TextStyle(color: _msg == 'Saved.' ? Colors.green : Colors.red),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  TextField(
                    controller: _feePerEntry,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Fee per animal / entry',
                      hintText: 'Example: 2.00',
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _feePerShow,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Optional: Fee per show (flat)',
                      hintText: 'Leave blank if not used',
                    ),
                  ),

                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Multi-show discount'),
                    value: _discountEnabled,
                    onChanged: _saving ? null : (v) => setState(() => _discountEnabled = v),
                  ),

                  if (_discountEnabled) ...[
                    DropdownButtonFormField<String>(
                      value: _discountType,
                      items: const [
                        DropdownMenuItem(value: 'amount', child: Text('Amount (\$ off)')),
                        DropdownMenuItem(value: 'percent', child: Text('Percent (% off)')),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _discountType = v ?? 'amount'),
                      decoration: const InputDecoration(labelText: 'Discount type'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _discountValue,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Discount value',
                        hintText: 'Example: 1.00 or 10',
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}