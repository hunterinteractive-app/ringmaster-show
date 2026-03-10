import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ShowPaymentSettingsDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => _ShowPaymentSettingsDialog(showId: showId, showName: showName),
    );
  }
}

class _ShowPaymentSettingsDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowPaymentSettingsDialog({required this.showId, required this.showName});

  @override
  State<_ShowPaymentSettingsDialog> createState() => _ShowPaymentSettingsDialogState();
}

class _ShowPaymentSettingsDialogState extends State<_ShowPaymentSettingsDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;

  String _paymentMode = 'pay_day_of_show'; // pay_day_of_show|stripe|square|hybrid
  bool _requirePaymentToSubmit = false;
  bool _allowRefunds = true;

  bool _stripeEnabled = false;
  final _stripePublishableKey = TextEditingController();
  final _stripeAccountId = TextEditingController();

  bool _squareEnabled = false;
  final _squareAppId = TextEditingController();
  final _squareLocationId = TextEditingController();

  @override
  void dispose() {
    _stripePublishableKey.dispose();
    _stripeAccountId.dispose();
    _squareAppId.dispose();
    _squareLocationId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final data = await supabase
          .from('show_payment_settings')
          .select(
              'payment_mode,require_payment_to_submit,allow_refunds,stripe_enabled,stripe_publishable_key,stripe_account_id,square_enabled,square_application_id,square_location_id')
          .eq('show_id', widget.showId)
          .maybeSingle();

      if (data != null) {
        _paymentMode = (data['payment_mode'] ?? 'pay_day_of_show').toString();
        _requirePaymentToSubmit = data['require_payment_to_submit'] == true;
        _allowRefunds = data['allow_refunds'] != false;

        _stripeEnabled = data['stripe_enabled'] == true;
        _stripePublishableKey.text = (data['stripe_publishable_key'] ?? '').toString();
        _stripeAccountId.text = (data['stripe_account_id'] ?? '').toString();

        _squareEnabled = data['square_enabled'] == true;
        _squareAppId.text = (data['square_application_id'] ?? '').toString();
        _squareLocationId.text = (data['square_location_id'] ?? '').toString();
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

  bool _validate() {
    if (_paymentMode == 'stripe' || _paymentMode == 'hybrid') {
      if (_stripeEnabled) {
        if (_stripePublishableKey.text.trim().isEmpty) {
          setState(() => _msg = 'Stripe publishable key is required when Stripe is enabled.');
          return false;
        }
      }
    }
    if (_paymentMode == 'square' || _paymentMode == 'hybrid') {
      if (_squareEnabled) {
        if (_squareAppId.text.trim().isEmpty) {
          setState(() => _msg = 'Square application id is required when Square is enabled.');
          return false;
        }
      }
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
      await supabase.from('show_payment_settings').upsert({
        'show_id': widget.showId,
        'payment_mode': _paymentMode,
        'require_payment_to_submit': _requirePaymentToSubmit,
        'allow_refunds': _allowRefunds,

        'stripe_enabled': _stripeEnabled,
        'stripe_publishable_key': _stripePublishableKey.text.trim().isEmpty ? null : _stripePublishableKey.text.trim(),
        'stripe_account_id': _stripeAccountId.text.trim().isEmpty ? null : _stripeAccountId.text.trim(),

        'square_enabled': _squareEnabled,
        'square_application_id': _squareAppId.text.trim().isEmpty ? null : _squareAppId.text.trim(),
        'square_location_id': _squareLocationId.text.trim().isEmpty ? null : _squareLocationId.text.trim(),

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
      title: Text('Payment Settings — ${widget.showName}'),
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

                  DropdownButtonFormField<String>(
                    value: _paymentMode,
                    items: const [
                      DropdownMenuItem(value: 'pay_day_of_show', child: Text('Pay Day of Show')),
                      DropdownMenuItem(value: 'stripe', child: Text('Stripe')),
                      DropdownMenuItem(value: 'square', child: Text('Square')),
                      DropdownMenuItem(value: 'hybrid', child: Text('Hybrid (Stripe + Square)')),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _paymentMode = v ?? 'pay_day_of_show'),
                    decoration: const InputDecoration(labelText: 'Payment mode'),
                  ),

                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require payment to submit (later)'),
                    subtitle: const Text('Keep OFF for MVP. Turn on when Stripe/Square flow is built.'),
                    value: _requirePaymentToSubmit,
                    onChanged: _saving ? null : (v) => setState(() => _requirePaymentToSubmit = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow refunds'),
                    value: _allowRefunds,
                    onChanged: _saving ? null : (v) => setState(() => _allowRefunds = v),
                  ),

                  const Divider(height: 24),

                  if (_paymentMode == 'stripe' || _paymentMode == 'hybrid') ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Stripe', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Stripe'),
                      value: _stripeEnabled,
                      onChanged: _saving ? null : (v) => setState(() => _stripeEnabled = v),
                    ),
                    TextField(
                      controller: _stripePublishableKey,
                      enabled: !_saving && _stripeEnabled,
                      decoration: const InputDecoration(labelText: 'Stripe publishable key'),
                    ),
                    TextField(
                      controller: _stripeAccountId,
                      enabled: !_saving && _stripeEnabled,
                      decoration: const InputDecoration(labelText: 'Stripe account id (optional)'),
                    ),
                    const Divider(height: 24),
                  ],

                  if (_paymentMode == 'square' || _paymentMode == 'hybrid') ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Square', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Square'),
                      value: _squareEnabled,
                      onChanged: _saving ? null : (v) => setState(() => _squareEnabled = v),
                    ),
                    TextField(
                      controller: _squareAppId,
                      enabled: !_saving && _squareEnabled,
                      decoration: const InputDecoration(labelText: 'Square application id'),
                    ),
                    TextField(
                      controller: _squareLocationId,
                      enabled: !_saving && _squareEnabled,
                      decoration: const InputDecoration(labelText: 'Square location id (optional)'),
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