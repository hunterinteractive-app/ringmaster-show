import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/stripe_connect_service.dart';

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
  bool _connectingStripe = false;
  bool _loadingStripeStatus = false;
  String? _msg;

  final _feePerEntry = TextEditingController();
  final _feePerShow = TextEditingController();
  final _furFee = TextEditingController();

  bool _discountEnabled = false;
  String _discountType = 'amount';
  final _discountValue = TextEditingController();

  Map<String, dynamic>? _stripeStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _feePerEntry.dispose();
    _feePerShow.dispose();
    _furFee.dispose();
    _discountValue.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final feeRow = await StripeConnectService.supabase
          .from('show_fee_settings')
          .select(
            'fee_per_entry,'
            'fee_per_show,'
            'fur_fee,'
            'multi_show_discount_enabled,'
            'multi_show_discount_type,'
            'multi_show_discount_value',
          )
          .eq('show_id', widget.showId)
          .maybeSingle();

      if (feeRow == null) {
        _feePerEntry.text = '0';
        _feePerShow.text = '';
        _furFee.text = '0';
        _discountEnabled = false;
        _discountType = 'amount';
        _discountValue.text = '0';
      } else {
        _feePerEntry.text = (feeRow['fee_per_entry'] ?? 0).toString();
        _feePerShow.text = feeRow['fee_per_show'] == null
            ? ''
            : feeRow['fee_per_show'].toString();
        _furFee.text = (feeRow['fur_fee'] ?? 0).toString();
        _discountEnabled = feeRow['multi_show_discount_enabled'] == true;
        _discountType =
            (feeRow['multi_show_discount_type'] ?? 'amount').toString();
        _discountValue.text =
            (feeRow['multi_show_discount_value'] ?? 0).toString();
      }

      await _loadStripeStatus(showErrorInBanner: false);

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
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
      setState(() => _msg = 'Fee per entry must be 0 or greater.');
      return false;
    }

    if (_feePerShow.text.trim().isNotEmpty) {
      final perShow = _parseMoney(_feePerShow.text);
      if (perShow == null) {
        setState(
          () => _msg = 'Fee per show must be 0 or greater, or left blank.',
        );
        return false;
      }
    }

    final furFee = _parseMoney(_furFee.text);
    if (furFee == null) {
      setState(() => _msg = 'Fur/Wool fee must be 0 or greater.');
      return false;
    }

    final disc = _parseMoney(_discountValue.text);
    if (disc == null) {
      setState(() => _msg = 'Discount must be 0 or greater.');
      return false;
    }

    if (_discountEnabled && _discountType == 'percent' && disc > 100) {
      setState(() => _msg = 'Percent discount cannot exceed 100.');
      return false;
    }

    return true;
  }

  Future<void> _connectStripe() async {
    setState(() {
      _connectingStripe = true;
      _msg = null;
    });

    try {
      final url = await StripeConnectService.startOnboarding(widget.showId);
      final uri = Uri.parse(url);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('Could not launch Stripe onboarding');
      }

      if (!mounted) return;
      setState(() {
        _msg =
            'Stripe onboarding opened. After completing it, come back and click Refresh Stripe Status.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Stripe setup failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _connectingStripe = false;
        });
      }
    }
  }

  Future<void> _openStripeDashboard() async {
    setState(() {
      _connectingStripe = true;
      _msg = null;
    });

    try {
      final url = await StripeConnectService.createLoginLink(widget.showId);
      final uri = Uri.parse(url);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('Could not launch Stripe dashboard');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Stripe dashboard failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _connectingStripe = false;
        });
      }
    }
  }

  Future<void> _loadStripeStatus({bool showErrorInBanner = true}) async {
    if (mounted) {
      setState(() {
        _loadingStripeStatus = true;
      });
    }

    try {
      final status = await StripeConnectService.getAccountStatus(widget.showId);

      if (!mounted) return;
      setState(() {
        _stripeStatus = status;
        _loadingStripeStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStripeStatus = false;
        if (showErrorInBanner) {
          _msg = 'Stripe status refresh failed: $e';
        }
      });
    }
  }

  Future<void> _refreshStripeStatus() async {
    await _loadStripeStatus(showErrorInBanner: true);
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await StripeConnectService.supabase.from('show_fee_settings').upsert({
        'show_id': widget.showId,
        'fee_per_entry': double.parse(_feePerEntry.text.trim()),
        'fee_per_show': _feePerShow.text.trim().isEmpty
            ? null
            : double.parse(_feePerShow.text.trim()),
        'fur_fee': double.parse(_furFee.text.trim()),
        'multi_show_discount_enabled': _discountEnabled,
        'multi_show_discount_type': _discountType,
        'multi_show_discount_value': double.parse(_discountValue.text.trim()),
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
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStripeStatusPill({
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStripeStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ready':
        return 'Ready to accept payments';
      case 'restricted':
        return 'Needs attention';
      case 'pending_onboarding':
        return 'Onboarding incomplete';
      case 'not_connected':
      default:
        return 'Not connected';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ready':
        return Colors.green;
      case 'restricted':
        return Colors.orange;
      case 'pending_onboarding':
        return Colors.blue;
      case 'not_connected':
      default:
        return Colors.red;
    }
  }

  String _prettyRequirement(String raw) {
    return raw
        .replaceAll('.', ' → ')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Widget _buildStripeSection() {
    final status = (_stripeStatus?['status'] ?? 'not_connected').toString();
    final color = _statusColor(status);
    final label = _statusLabel(status);

    final showPaymentAccount =
        _stripeStatus?['show_payment_account'] as Map<String, dynamic>?;
    final providerAccountId =
        (showPaymentAccount?['provider_account_id'] ?? '').toString();

    final chargesEnabled = _stripeStatus?['charges_enabled'] == true;
    final payoutsEnabled = _stripeStatus?['payouts_enabled'] == true;
    final detailsSubmitted = _stripeStatus?['details_submitted'] == true;

    final requirements =
        (_stripeStatus?['requirements'] as Map<String, dynamic>?) ?? {};
    final currentlyDue =
        (requirements['currently_due'] as List?)?.cast<dynamic>() ?? const [];
    final pastDue =
        (requirements['past_due'] as List?)?.cast<dynamic>() ?? const [];
    final pendingVerification =
        (requirements['pending_verification'] as List?)?.cast<dynamic>() ??
            const [];

    final connected = providerAccountId.isNotEmpty;
    final isReady = status == 'ready';
    final needsSetup = connected && !isReady;

    return _section('Online Payments', [
      const Text(
        'Connect Stripe so exhibitors can pay online. RingMaster uses a Stripe Connect marketplace flow so clubs receive funds directly, while RingMaster keeps a 2% platform fee from the club payout.',
      ),
      const SizedBox(height: 12),
      if (_loadingStripeStatus)
        const LinearProgressIndicator()
      else ...[
        Row(
          children: [
            _buildStripeStatusPill(
              text: label,
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildStripeStatusRow(
          'Stripe account',
          providerAccountId.isEmpty ? '—' : providerAccountId,
        ),
        _buildStripeStatusRow(
          'Charges enabled',
          chargesEnabled ? 'Yes' : 'No',
        ),
        _buildStripeStatusRow(
          'Payouts enabled',
          payoutsEnabled ? 'Yes' : 'No',
        ),
        _buildStripeStatusRow(
          'Details submitted',
          detailsSubmitted ? 'Yes' : 'No',
        ),
        if (currentlyDue.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildStripeStatusRow(
            'Currently due',
            currentlyDue
                .map((e) => _prettyRequirement(e.toString()))
                .join(', '),
          ),
        ],
        if (pastDue.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildStripeStatusRow(
            'Past due',
            pastDue.map((e) => _prettyRequirement(e.toString())).join(', '),
          ),
        ],
        if (pendingVerification.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildStripeStatusRow(
            'Pending verification',
            pendingVerification
                .map((e) => _prettyRequirement(e.toString()))
                .join(', '),
          ),
        ],
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.account_balance),
              label: Text(
                _connectingStripe
                    ? 'Opening...'
                    : !connected
                        ? 'Connect Stripe'
                        : needsSetup
                            ? 'Continue Stripe Setup'
                            : 'Open Stripe Dashboard',
              ),
              onPressed:
                  (_saving || _connectingStripe || _loadingStripeStatus)
                      ? null
                      : () async {
                          if (!connected || needsSetup) {
                            await _connectStripe();
                          } else {
                            await _openStripeDashboard();
                          }
                        },
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Stripe Status'),
              onPressed:
                  (_saving || _connectingStripe || _loadingStripeStatus)
                      ? null
                      : _refreshStripeStatus,
            ),
          ),
        ],
      ),
    ]);
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
                    onPressed: (_saving || _connectingStripe)
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F6FB),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
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
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _msg!,
                                  style: TextStyle(
                                    color: success ? Colors.green : Colors.red,
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
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Fee per animal / entry',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _furFee,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Fur / Wool fee',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _feePerShow,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Optional: Fee per show',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ]),
                                    _section('Discounts', [
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Enable multi-show discount',
                                        ),
                                        value: _discountEnabled,
                                        onChanged: _saving
                                            ? null
                                            : (v) => setState(
                                                  () => _discountEnabled = v,
                                                ),
                                      ),
                                      if (_discountEnabled) ...[
                                        const SizedBox(height: 8),
                                        DropdownButtonFormField<String>(
                                          value: _discountType,
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'amount',
                                              child: Text('Amount (\$ off)'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'percent',
                                              child: Text('Percent (% off)'),
                                            ),
                                          ],
                                          onChanged: _saving
                                              ? null
                                              : (v) => setState(
                                                    () => _discountType =
                                                        v ?? 'amount',
                                                  ),
                                          decoration: const InputDecoration(
                                            labelText: 'Discount type',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _discountValue,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          decoration: const InputDecoration(
                                            labelText: 'Discount value',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ],
                                    ]),
                                    _buildStripeSection(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: (_saving || _connectingStripe)
                                        ? null
                                        : () => Navigator.pop(context),
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
                                    onPressed:
                                        (_saving || _connectingStripe)
                                            ? null
                                            : _save,
                                    child: Text(_saving ? 'Saving…' : 'Save'),
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