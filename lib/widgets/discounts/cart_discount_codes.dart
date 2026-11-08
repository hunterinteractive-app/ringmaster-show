import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class CartDiscountCodes extends StatefulWidget {
  const CartDiscountCodes({
    super.key,
    required this.exhibitors,
    required this.codes,
    required this.apply,
    this.disabled = false,
  });
  final Map<String, String> exhibitors;
  final List<Map<String, dynamic>> codes;
  final Future<void> Function(String code, String exhibitorId) apply;
  final bool disabled;
  @override
  State<CartDiscountCodes> createState() => _CartDiscountCodesState();
}

class _CartDiscountCodesState extends State<CartDiscountCodes> {
  final _code = TextEditingController();
  String? _selected;
  String? _message;
  bool _busy = false;
  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final exhibitor =
        _selected ??
        (widget.exhibitors.length == 1 ? widget.exhibitors.keys.single : null);
    if (exhibitor == null || _code.text.trim().isEmpty) {
      setState(() => _message = 'Select the exhibitor and enter a code.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.apply(_code.text.trim(), exhibitor);
      if (mounted) {
        _code.clear();
        setState(
          () => _message =
              'Code saved. The best eligible discount is applied automatically.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppTheme.surfaceTextScope(
    context,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Discount code',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (widget.exhibitors.length > 1) ...[
          DropdownButtonFormField<String>(
            initialValue: _selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Apply for exhibitor'),
            items: widget.exhibitors.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: _busy || widget.disabled
                ? null
                : (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _code,
                enabled: !_busy && !widget.disabled,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Club member code',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  if (!_busy && !widget.disabled) _apply();
                },
              ),
            ),
            OutlinedButton(
              onPressed: _busy || widget.disabled ? null : _apply,
              child: Text(_busy ? 'Applying…' : 'Apply Code'),
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_message!),
          ),
        for (final code in widget.codes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${widget.exhibitors[code['exhibitor_id']] ?? 'Exhibitor'}: ${code['code']}${code['enabled'] == true ? ' saved for this show' : ' (disabled by show)'}',
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Your best eligible discount is used, without stacking. Savings already received are counted; unused overall savings carry forward to later checkouts for this exhibitor and show.',
          ),
        ),
      ],
    ),
  );
}
