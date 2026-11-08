import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/entry_discount_service.dart';
import '../../theme/app_theme.dart';

/// Code changes save independently of the surrounding show-fee form.
class ShowDiscountCodes extends StatefulWidget {
  const ShowDiscountCodes({
    super.key,
    required this.showId,
    this.readOnly = false,
  });
  final String showId;
  final bool readOnly;
  @override
  State<ShowDiscountCodes> createState() => _ShowDiscountCodesState();
}

class _ShowDiscountCodesState extends State<ShowDiscountCodes> {
  List<Map<String, dynamic>> _rules = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rules = await EntryDiscountService.manage(showId: widget.showId);
      if (mounted) {
        setState(() {
          _rules = rules;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load discount codes. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? rule]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
        child: _CodeEditor(showId: widget.showId, rule: rule),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _busy = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Club member discount codes',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Exhibitors enter a code in their cart. Codes stay with the exhibitor for this show across checkouts. The best eligible discount applies; discounts do not stack.',
      ),
      const SizedBox(height: 8),
      const Text(
        'Entry fees only. Overall dollar discounts are available once per exhibitor for the show, with unused savings carried forward. Add-ons, fur, per-show fees and exhibitor fees are excluded.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Row(
          children: [
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      for (final rule in _rules)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${rule['code']} — ${rule['label']}'),
          subtitle: Text(
            '${rule['discount_type'] == 'percent' ? '${rule['value']}%' : rule['value']} ${rule['discount_type'] == 'fixed_rate' ? 'entry rate' : 'off'} • ${rule['basis'] == 'overall' ? 'Overall per exhibitor' : 'Per entry'} • ${rule['enabled'] == true ? 'Active' : 'Disabled'}',
          ),
          trailing: IconButton(
            tooltip: 'Edit discount code',
            onPressed: widget.readOnly || _busy ? null : () => _edit(rule),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
      OutlinedButton.icon(
        onPressed: widget.readOnly || _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add discount code'),
      ),
      const Text('Each code is saved here using Save Code.'),
    ],
  );
}

class _CodeEditor extends StatefulWidget {
  const _CodeEditor({required this.showId, this.rule});
  final String showId;
  final Map<String, dynamic>? rule;
  @override
  State<_CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<_CodeEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _code = TextEditingController(
    text: widget.rule?['code']?.toString(),
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.rule?['label']?.toString() ?? 'Club member discount',
  );
  late final TextEditingController _value = TextEditingController(
    text: widget.rule?['value']?.toString() ?? '',
  );
  late String _type = widget.rule?['discount_type']?.toString() ?? 'amount';
  late String _basis = widget.rule?['basis']?.toString() ?? 'per_entry';
  late bool _enabled =
      widget.rule?['enabled'] == null || widget.rule?['enabled'] == true;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  void _generate() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    _code.text = List.generate(
      10,
      (_) => letters[random.nextInt(letters.length)],
    ).join();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await EntryDiscountService.manage(
        showId: widget.showId,
        rule: {
          'id': widget.rule?['id'],
          'code': _code.text.trim().toUpperCase(),
          'label': _label.text.trim(),
          'discount_type': _type,
          'basis': _basis,
          'value': double.parse(_value.text),
          'enabled': _enabled,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not save. Check that this code is unique for the show and the show is unlocked.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.rule == null ? 'New discount code' : 'Edit discount code',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Discount name'),
                validator: (v) =>
                    v == null || v.trim().isEmpty || v.trim().length > 100
                    ? 'Enter a name (up to 100 characters).'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _code,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Code',
                  helperText:
                      '4–32 letters, numbers or hyphens. Not case-sensitive.',
                ),
                validator: (v) =>
                    RegExp(
                      r'^[A-Z0-9][A-Z0-9-]{3,31}$',
                    ).hasMatch((v ?? '').trim().toUpperCase())
                    ? null
                    : 'Enter a valid code or generate one.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : _generate,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Generate Code'),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _basis,
                decoration: const InputDecoration(labelText: 'Apply discount'),
                items: const [
                  DropdownMenuItem(
                    value: 'per_entry',
                    child: Text('Per entry'),
                  ),
                  DropdownMenuItem(
                    value: 'overall',
                    child: Text(
                      'Overall per exhibitor',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                isExpanded: true,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        _basis = v!;
                        if (_basis == 'overall' && _type == 'fixed_rate') {
                          _type = 'amount';
                        }
                      }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('$_basis-$_type'),
                isExpanded: true,
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Discount type'),
                items: [
                  const DropdownMenuItem(
                    value: 'amount',
                    child: Text('Dollar amount off'),
                  ),
                  const DropdownMenuItem(
                    value: 'percent',
                    child: Text('Percentage off'),
                  ),
                  if (_basis == 'per_entry')
                    const DropdownMenuItem(
                      value: 'fixed_rate',
                      child: Text('Reduced entry rate'),
                    ),
                ],
                onChanged: _saving ? null : (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _value,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _type == 'percent'
                      ? 'Percent (0–100)'
                      : 'Amount in the show’s currency',
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return n == null ||
                          !n.isFinite ||
                          n < 0 ||
                          n > (_type == 'percent' ? 100 : 100000) ||
                          !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v ?? '')
                      ? 'Enter a valid amount with up to two decimal places.'
                      : null;
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: _enabled,
                onChanged: _saving ? null : (v) => setState(() => _enabled = v),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        child: Text(_saving ? 'Saving…' : 'Save Code'),
      ),
    ],
  );
}
