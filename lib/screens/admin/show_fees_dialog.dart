// lib/screens/admin/show_fees_dialog.dart


import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ringmaster_show/services/show_lock_service.dart';

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

  bool _discountEnabled = false;
  String _discountType = 'amount';
  final _discountValue = TextEditingController();

  final Map<String, TextEditingController> _feePerEntryBySection = {};
  final Map<String, TextEditingController> _feePerShowBySection = {};
  final Map<String, TextEditingController> _furFeeBySection = {};

  List<Map<String, dynamic>> _sections = [];
  Map<String, dynamic>? _stripeStatus;

  bool _isLocked = false;
  bool _isFinalized = false;

  bool get _isReadOnly => _isLocked || _isFinalized;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _discountValue.dispose();

    for (final c in _feePerEntryBySection.values) {
      c.dispose();
    }
    for (final c in _feePerShowBySection.values) {
      c.dispose();
    }
    for (final c in _furFeeBySection.values) {
      c.dispose();
    }

    super.dispose();
  }

  TextEditingController _entryControllerFor(String sectionId) {
    return _feePerEntryBySection.putIfAbsent(
      sectionId,
      () => TextEditingController(),
    );
  }

  TextEditingController _showControllerFor(String sectionId) {
    return _feePerShowBySection.putIfAbsent(
      sectionId,
      () => TextEditingController(),
    );
  }

  TextEditingController _furControllerFor(String sectionId) {
    return _furFeeBySection.putIfAbsent(
      sectionId,
      () => TextEditingController(),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final show = await StripeConnectService.supabase
          .from('shows')
          .select('is_locked,finalized_at')
          .eq('id', widget.showId)
          .single();

      _isLocked = show['is_locked'] == true;
      _isFinalized = (show['finalized_at'] ?? '').toString().trim().isNotEmpty;

      final feeRow = await StripeConnectService.supabase
          .from('show_fee_settings')
          .select(
            'currency,'
            'multi_show_discount_enabled,'
            'multi_show_discount_type,'
            'multi_show_discount_value',
          )
          .eq('show_id', widget.showId)
          .maybeSingle();

      final sectionsRes = await StripeConnectService.supabase
          .from('show_sections')
          .select('id,display_name,kind,letter,sort_order')
          .eq('show_id', widget.showId)
          .eq('is_enabled', true)
          .order('sort_order');

      final sections = (sectionsRes as List).cast<Map<String, dynamic>>();

      final sectionIds = sections
          .map((s) => s['id'].toString())
          .where((id) => id.isNotEmpty)
          .toList();

      final sectionFeeRes = sectionIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await StripeConnectService.supabase
              .from('show_section_fee_settings')
              .select('section_id,fee_per_entry,fee_per_show,fur_fee')
              .inFilter('section_id', sectionIds);

      final sectionFeeRows =
          (sectionFeeRes as List).cast<Map<String, dynamic>>();
      final feeBySectionId = {
        for (final row in sectionFeeRows) row['section_id'].toString(): row,
      };

      _discountEnabled = feeRow?['multi_show_discount_enabled'] == true;
      _discountType =
          (feeRow?['multi_show_discount_type'] ?? 'amount').toString();
      _discountValue.text =
          (feeRow?['multi_show_discount_value'] ?? 0).toString();

      for (final section in sections) {
        final sectionId = section['id'].toString();
        final row = feeBySectionId[sectionId];

        _entryControllerFor(sectionId).text =
            (row?['fee_per_entry'] ?? 0).toString();

        _showControllerFor(sectionId).text = row?['fee_per_show'] == null
            ? ''
            : row!['fee_per_show'].toString();

        _furControllerFor(sectionId).text =
            (row?['fur_fee'] ?? 0).toString();
      }

      await _loadStripeStatus(showErrorInBanner: false);

      if (!mounted) return;
      setState(() {
        _sections = sections;
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

  String _sectionLabel(Map<String, dynamic> section) {
    final display = (section['display_name'] ?? '').toString().trim();
    if (display.isNotEmpty) return display;

    final kind = (section['kind'] ?? '').toString().trim().toLowerCase();
    final letter = (section['letter'] ?? '').toString().trim().toUpperCase();

    final kindLabel = kind == 'youth'
        ? 'Youth'
        : kind == 'open'
            ? 'Open'
            : 'Section';

    return letter.isEmpty ? kindLabel : '$kindLabel $letter';
  }

  bool _validate() {
    for (final section in _sections) {
      final sectionId = section['id'].toString();
      final sectionName = _sectionLabel(section);

      final perEntry = _parseMoney(_entryControllerFor(sectionId).text);
      if (perEntry == null) {
        setState(() => _msg = '$sectionName fee per entry must be 0 or greater.');
        return false;
      }

      final feePerShowText = _showControllerFor(sectionId).text.trim();
      if (feePerShowText.isNotEmpty) {
        final perShow = _parseMoney(feePerShowText);
        if (perShow == null) {
          setState(() => _msg =
              '$sectionName fee per show must be 0 or greater, or left blank.');
          return false;
        }
      }

      final furFee = _parseMoney(_furControllerFor(sectionId).text);
      if (furFee == null) {
        setState(() => _msg = '$sectionName Fur/Wool fee must be 0 or greater.');
        return false;
      }
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
      await ShowLockService.assertShowUnlocked(widget.showId);
      await StripeConnectService.supabase.from('show_fee_settings').upsert({
        'show_id': widget.showId,
        'multi_show_discount_enabled': _discountEnabled,
        'multi_show_discount_type': _discountType,
        'multi_show_discount_value': double.parse(_discountValue.text.trim()),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final sectionRows = _sections.map((section) {
        final sectionId = section['id'].toString();

        return {
          'section_id': sectionId,
          'fee_per_entry':
              double.parse(_entryControllerFor(sectionId).text.trim()),
          'fee_per_show': _showControllerFor(sectionId).text.trim().isEmpty
              ? null
              : double.parse(_showControllerFor(sectionId).text.trim()),
          'fur_fee': double.parse(_furControllerFor(sectionId).text.trim()),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
      }).toList();

      if (sectionRows.isNotEmpty) {
        await StripeConnectService.supabase
            .from('show_section_fee_settings')
            .upsert(sectionRows);
      }

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

    Widget _section(
    String title,
    List<Widget> children, {
    String? subtitle,
    IconData? icon,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: const Color(0xFF11285A)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _moneyField({
    required TextEditingController controller,
    required String label,
    String? helper,
  }) {
    return TextField(
      controller: controller,
      enabled: !_saving && !_isReadOnly,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixText: '\$ ',
        border: const OutlineInputBorder(),
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
    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 10, bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
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

  Widget _buildSectionFeesSection() {
    if (_sections.isEmpty) {
      return _section(
        'Entry Fees',
        const [Text('No enabled show sections found.')],
        icon: Icons.confirmation_number_outlined,
      );
    }

    return _section(
      'Entry Fees by Show Section',
      [
        Text(
          'Set the standard animal entry fee, optional flat show fee, and Fur/Wool fee for each enabled section.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        ..._sections.map((section) {
          final sectionId = section['id'].toString();
          final title = _sectionLabel(section);

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFD),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stack = constraints.maxWidth < 620;

                    final fields = [
                      _moneyField(
                        controller: _entryControllerFor(sectionId),
                        label: 'Fee per animal / entry',
                      ),
                      _moneyField(
                        controller: _furControllerFor(sectionId),
                        label: 'Fur / Wool fee',
                      ),
//                      _moneyField(
//                        controller: _showControllerFor(sectionId),
//                        label: 'Optional fee per show',
//                        helper: 'Leave blank if not used',
//                      ),
                    ];

                    if (stack) {
                      return Column(
                        children: [
                          for (final field in fields) ...[
                            field,
                            const SizedBox(height: 12),
                          ],
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < fields.length; i++) ...[
                          Expanded(child: fields[i]),
                          if (i != fields.length - 1)
                            const SizedBox(width: 12),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        }),
      ],
      icon: Icons.attach_money,
    );
  }

  Widget _buildDiscountSection() {
    return _section(
      'Discounts',
      [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Enable multi-show discount',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Applies a discount when an exhibitor enters multiple show sections.',
          ),
          value: _discountEnabled,
          onChanged: (_saving || _isReadOnly)
              ? null
              : (v) => setState(() => _discountEnabled = v),
        ),
        if (_discountEnabled) ...[
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 520;

              final typeField = DropdownButtonFormField<String>(
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
                onChanged: (_saving || _isReadOnly)
                    ? null
                    : (v) => setState(() => _discountType = v ?? 'amount'),
                decoration: const InputDecoration(
                  labelText: 'Discount type',
                  border: OutlineInputBorder(),
                ),
              );

              final valueField = TextField(
                controller: _discountValue,
                enabled: !_saving && !_isReadOnly,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Discount value',
                  prefixText: _discountType == 'amount' ? '\$ ' : null,
                  suffixText: _discountType == 'percent' ? '%' : null,
                  border: const OutlineInputBorder(),
                ),
              );

              if (stack) {
                return Column(
                  children: [
                    typeField,
                    const SizedBox(height: 12),
                    valueField,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: typeField),
                  const SizedBox(width: 12),
                  Expanded(child: valueField),
                ],
              );
            },
          ),
        ],
      ],
      icon: Icons.discount_outlined,
    );
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

    return _section(
      'Online Payments',
      [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF11285A).withOpacity(.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF11285A).withOpacity(.10),
            ),
          ),
          child: const Text(
            'Connect Stripe so exhibitors can pay online. Clubs receive funds through Stripe Connect, and RingMaster keeps a 2% platform fee from the club payout.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 14),
        if (_loadingStripeStatus)
          const LinearProgressIndicator()
        else ...[
          Row(
            children: [
              _buildStripeStatusPill(text: label, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            children: [
              _buildStripeStatusRow(
                'Stripe account',
                providerAccountId.isEmpty ? '—' : providerAccountId,
              ),
              _buildStripeStatusRow(
                'Charges',
                chargesEnabled ? 'Enabled' : 'Not enabled',
              ),
              _buildStripeStatusRow(
                'Payouts',
                payoutsEnabled ? 'Enabled' : 'Not enabled',
              ),
              _buildStripeStatusRow(
                'Details',
                detailsSubmitted ? 'Submitted' : 'Not submitted',
              ),
            ],
          ),
          if (currentlyDue.isNotEmpty ||
              pastDue.isNotEmpty ||
              pendingVerification.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(.20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stripe requirements',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  if (currentlyDue.isNotEmpty)
                    Text(
                      'Currently due: ${currentlyDue.map((e) => _prettyRequirement(e.toString())).join(', ')}',
                    ),
                  if (pastDue.isNotEmpty)
                    Text(
                      'Past due: ${pastDue.map((e) => _prettyRequirement(e.toString())).join(', ')}',
                    ),
                  if (pendingVerification.isNotEmpty)
                    Text(
                      'Pending verification: ${pendingVerification.map((e) => _prettyRequirement(e.toString())).join(', ')}',
                    ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 520;

            final primary = FilledButton.icon(
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
              onPressed: (_saving || _isReadOnly || _connectingStripe || _loadingStripeStatus)
                  ? null
                  : () async {
                      if (!connected || needsSetup) {
                        await _connectStripe();
                      } else {
                        await _openStripeDashboard();
                      }
                    },
            );

            final refresh = OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Status'),
              onPressed: (_saving || _isReadOnly || _connectingStripe || _loadingStripeStatus)
                  ? null
                  : _refreshStripeStatus,
            );

            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  primary,
                  const SizedBox(height: 10),
                  refresh,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: primary),
                const SizedBox(width: 12),
                Expanded(child: refresh),
              ],
            );
          },
        ),
      ],
      icon: Icons.payments_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final success = _msg == 'Saved.';

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: media.width < 760 ? media.width - 16 : 760,
          maxHeight: media.height < 840 ? media.height * 0.94 : 800,
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
                      'Show Fees & Payments — ${widget.showName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
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
                                  border: Border.all(
                                    color: success
                                        ? Colors.green.withOpacity(.25)
                                        : Colors.red.withOpacity(.25),
                                  ),
                                ),
                                child: Text(
                                  _msg!,
                                  style: TextStyle(
                                    color:
                                        success ? Colors.green.shade700 : Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildSectionFeesSection(),
                                    _buildDiscountSection(),
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
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFD4A623),
                                      foregroundColor: Colors.black87,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                    ),
                                    onPressed: (_saving || _isReadOnly || _connectingStripe)
                                        ? null
                                        : _save,
                                    icon: const Icon(Icons.save_outlined),
                                    label: Text(_saving ? 'Saving…' : 'Save Changes'),
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