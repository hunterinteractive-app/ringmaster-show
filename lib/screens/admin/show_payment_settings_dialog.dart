// lib/screens/admin/show_payment_settings_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';

final supabase = Supabase.instance.client;

class ShowPaymentSettingsDialog {
  static Future<void> open(
    BuildContext context, {
    required String showId,
    required String showName,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShowPaymentSettingsDialog(
        showId: showId,
        showName: showName,
      ),
    );
  }
}

class _ShowPaymentSettingsDialog extends StatefulWidget {
  final String showId;
  final String showName;

  const _ShowPaymentSettingsDialog({
    required this.showId,
    required this.showName,
  });

  @override
  State<_ShowPaymentSettingsDialog> createState() =>
      _ShowPaymentSettingsDialogState();
}

class _ShowPaymentSettingsDialogState
    extends State<_ShowPaymentSettingsDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _msg;
  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  String _paymentMode =
      'pay_day_of_show'; // pay_day_of_show|stripe|square|hybrid
  bool _requirePaymentToSubmit = false;
  bool _allowRefunds = true;

  bool _stripeEnabled = false;
  final _stripePublishableKey = TextEditingController();
  final _stripeAccountId = TextEditingController();

  bool _stripeChargesEnabled = false;
  bool _stripePayoutsEnabled = false;
  bool _stripeDetailsSubmitted = false;
  String _stripeAccountStatus = '';

  bool get _stripeHasAccount => _stripeAccountId.text.trim().isNotEmpty;

  bool get _stripeReady =>
      _stripeHasAccount &&
      _stripeChargesEnabled &&
      _stripePayoutsEnabled &&
      _stripeDetailsSubmitted &&
      _stripeAccountStatus.toLowerCase().trim() != 'restricted';

  bool _squareEnabled = false;
  final _squareAppId = TextEditingController();
  final _squareLocationId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

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
      final show = await supabase
          .from('shows')
          .select('is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();

      _isLocked = show['is_locked'] == true;
      _isFinalized = (show['finalized_at'] ?? '').toString().trim().isNotEmpty;
      final data = await supabase
          .from('show_payment_settings')
          .select(
            'payment_mode,require_payment_to_submit,allow_refunds,'
            'stripe_enabled,stripe_publishable_key,stripe_account_id,'
            'square_enabled,square_application_id,square_location_id',
          )
          .eq('show_id', widget.showId)
          .maybeSingle();

      if (data != null) {
        _paymentMode = (data['payment_mode'] ?? 'pay_day_of_show').toString();
        _requirePaymentToSubmit = data['require_payment_to_submit'] == true;
        _allowRefunds = data['allow_refunds'] != false;

        _stripeEnabled = data['stripe_enabled'] == true;
        _stripePublishableKey.text =
            (data['stripe_publishable_key'] ?? '').toString();
        _stripeAccountId.text = (data['stripe_account_id'] ?? '').toString();

        _squareEnabled = data['square_enabled'] == true;
        _squareAppId.text = (data['square_application_id'] ?? '').toString();
        _squareLocationId.text = (data['square_location_id'] ?? '').toString();
      }

      final stripeLinkRows = await supabase
          .from('show_payment_account_links')
          .select(
            'stripe_account_id,charges_enabled,payouts_enabled,details_submitted,account_status,updated_at,created_at',
          )
          .eq('show_id', widget.showId)
          .eq('provider', 'stripe')
          .order('updated_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(1);

      final stripeLinks = List<Map<String, dynamic>>.from(stripeLinkRows);
      if (stripeLinks.isNotEmpty) {
        final stripeLink = stripeLinks.first;
        final connectedAccountId =
            (stripeLink['stripe_account_id'] ?? '').toString().trim();
        if (connectedAccountId.isNotEmpty) {
          _stripeAccountId.text = connectedAccountId;
        }
        _stripeChargesEnabled = stripeLink['charges_enabled'] == true;
        _stripePayoutsEnabled = stripeLink['payouts_enabled'] == true;
        _stripeDetailsSubmitted = stripeLink['details_submitted'] == true;
        _stripeAccountStatus = (stripeLink['account_status'] ?? '').toString();
      } else {
        _stripeChargesEnabled = false;
        _stripePayoutsEnabled = false;
        _stripeDetailsSubmitted = false;
        _stripeAccountStatus = '';
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
    if (_isReadOnly) {
      setState(() => _msg = _isFinalized
          ? 'This show has been finalized. Payment settings can no longer be changed.'
          : 'This show is locked. Payment settings can no longer be changed.');
      return false;
    }
    if ((_paymentMode == 'stripe' || _paymentMode == 'hybrid') &&
        _stripeEnabled &&
        !_stripeHasAccount) {
      setState(() {
        _msg = 'Connect Stripe before enabling online Stripe payments.';
      });
      return false;
    }

    if ((_paymentMode == 'square' || _paymentMode == 'hybrid') &&
        _squareEnabled) {
      if (_squareAppId.text.trim().isEmpty) {
        setState(() {
          _msg = 'Square application id is required when Square is enabled.';
        });
        return false;
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
      await ShowLockService.assertShowUnlocked(widget.showId);
      await supabase.from('show_payment_settings').upsert({
        'show_id': widget.showId,
        'payment_mode': _paymentMode,
        'require_payment_to_submit': _requirePaymentToSubmit,
        'allow_refunds': _allowRefunds,
        'stripe_enabled': _stripeEnabled,
        'stripe_publishable_key': _stripePublishableKey.text.trim().isEmpty
            ? null
            : _stripePublishableKey.text.trim(),
        'stripe_account_id': _stripeAccountId.text.trim().isEmpty
            ? null
            : _stripeAccountId.text.trim(),
        'square_enabled': _squareEnabled,
        'square_application_id': _squareAppId.text.trim().isEmpty
            ? null
            : _squareAppId.text.trim(),
        'square_location_id': _squareLocationId.text.trim().isEmpty
            ? null
            : _squareLocationId.text.trim(),
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

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
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
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final savedMessage = _msg == 'Saved.';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.width < 700 ? media.width - 16 : media.width * 0.76,
          maxHeight: media.height * 0.92,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF11285A),
                Color(0xFF0B1C43),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
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
                      height: 38,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Payment Settings — ${widget.showName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F6FB),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          child: Column(
                            children: [
                              if (_isReadOnly) ...[
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.amber.shade300),
                                  ),
                                  child: Text(
                                    _isFinalized
                                        ? 'This show has been finalized. Payment settings are view-only.'
                                        : 'This show is locked. Payment settings are view-only.',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                              if (_msg != null)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: savedMessage
                                        ? Colors.green.withOpacity(.08)
                                        : Colors.red.withOpacity(.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: savedMessage
                                          ? Colors.green.withOpacity(.25)
                                          : Colors.red.withOpacity(.25),
                                    ),
                                  ),
                                  child: Text(
                                    _msg!,
                                    style: TextStyle(
                                      color: savedMessage
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
                                      _buildSectionCard(
                                        context: context,
                                        title: 'Payment Mode',
                                        children: [
                                          DropdownButtonFormField<String>(
                                            value: _paymentMode,
                                            decoration: const InputDecoration(
                                              labelText: 'Payment mode',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                value: 'pay_day_of_show',
                                                child: Text('Pay Day of Show'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'stripe',
                                                child: Text('Stripe'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'square',
                                                child: Text('Square'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'hybrid',
                                                child: Text(
                                                  'Hybrid (Stripe + Square)',
                                                ),
                                              ),
                                            ],
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                      () => _paymentMode =
                                                          v ??
                                                              'pay_day_of_show',
                                                    ),
                                          ),
                                          const SizedBox(height: 12),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text(
                                              'Require payment to submit',
                                            ),
                                            subtitle: const Text(
                                              'Keep OFF for MVP until live payment flow is fully built.',
                                            ),
                                            value: _requirePaymentToSubmit,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                      () => _requirePaymentToSubmit =
                                                          v,
                                                    ),
                                          ),
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            title: const Text('Allow refunds'),
                                            value: _allowRefunds,
                                            onChanged: (_saving || _isReadOnly)
                                                ? null
                                                : (v) => setState(
                                                      () => _allowRefunds = v,
                                                    ),
                                          ),
                                        ],
                                      ),
                                      if (_paymentMode == 'stripe' ||
                                          _paymentMode == 'hybrid')
                                        _buildSectionCard(
                                          context: context,
                                          title: 'Stripe',
                                          children: [
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: _stripeReady
                                                    ? Colors.green.withOpacity(.08)
                                                    : Colors.orange.withOpacity(.10),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: _stripeReady
                                                      ? Colors.green.withOpacity(.25)
                                                      : Colors.orange.withOpacity(.35),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _stripeReady
                                                        ? 'Ready to accept online payments'
                                                        : (_stripeHasAccount
                                                            ? 'Stripe setup incomplete'
                                                            : 'Stripe not connected'),
                                                    style: TextStyle(
                                                      color: _stripeReady
                                                          ? Colors.green.shade700
                                                          : Colors.orange.shade900,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 18,
                                                    runSpacing: 6,
                                                    children: [
                                                      Text(
                                                        'Stripe account: ${_stripeHasAccount ? _stripeAccountId.text.trim() : '—'}',
                                                      ),
                                                      Text(
                                                        'Charges: ${_stripeChargesEnabled ? 'Enabled' : 'Not enabled'}',
                                                      ),
                                                      Text(
                                                        'Payouts: ${_stripePayoutsEnabled ? 'Enabled' : 'Not enabled'}',
                                                      ),
                                                      Text(
                                                        'Details: ${_stripeDetailsSubmitted ? 'Submitted' : 'Incomplete'}',
                                                      ),
                                                      if (_stripeAccountStatus
                                                          .trim()
                                                          .isNotEmpty)
                                                        Text(
                                                          'Status: $_stripeAccountStatus',
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: const Text('Enable Stripe'),
                                              subtitle: const Text(
                                                'Only enable this after Stripe shows ready to accept online payments.',
                                              ),
                                              value: _stripeEnabled,
                                              onChanged: (_saving ||
                                                      _isReadOnly ||
                                                      !_stripeReady)
                                                  ? null
                                                  : (v) => setState(
                                                        () => _stripeEnabled =
                                                            v,
                                                      ),
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: _stripePublishableKey,
                                              enabled: !_saving && !_isReadOnly && _stripeEnabled,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Stripe publishable key',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: _stripeAccountId,
                                              enabled: false,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Connected Stripe account id',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (_paymentMode == 'square' ||
                                          _paymentMode == 'hybrid')
                                        _buildSectionCard(
                                          context: context,
                                          title: 'Square',
                                          children: [
                                            SwitchListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: const Text('Enable Square'),
                                              value: _squareEnabled,
                                              onChanged: (_saving || _isReadOnly)
                                                  ? null
                                                  : (v) => setState(
                                                        () => _squareEnabled =
                                                            v,
                                                      ),
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: _squareAppId,
                                              enabled: !_saving && !_isReadOnly && _squareEnabled,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Square application id',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            TextField(
                                              controller: _squareLocationId,
                                              enabled: !_saving && !_isReadOnly && _squareEnabled,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    'Square location id (optional)',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed:
                                          _saving ? null : () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFFD4A623),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                      ),
                                      onPressed: (_saving || _isReadOnly) ? null : _save,
                                      child: Text(
                                        _saving
                                            ? 'Saving…'
                                            : _isReadOnly
                                                ? 'View Only'
                                                : 'Save',
                                      ),
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
      ),
    );
  }
}