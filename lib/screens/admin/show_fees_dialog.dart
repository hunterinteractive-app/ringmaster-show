// lib/screens/admin/show_fees_dialog.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
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
  bool _connectingStripe = false;
  bool _loadingStripeStatus = false;
  String? _msg;

  bool _discountEnabled = false;
  String _discountType = 'amount';
  final _discountValue = TextEditingController();
  String _discountBasis = 'each_show';
  String _discountScope = 'both';
  final _discountMinimumEntries = TextEditingController();
  final _discountMaximumEntries = TextEditingController();
  final _discountRequiredShows = TextEditingController();

  String _onlinePaymentFeeMode = 'club_absorbs';
  static const String _onlinePaymentFeeDisclosure =
      'This show charges an Online Payment Fee for electronic payments. This fee helps cover payment processing costs, payment provider charges, and online entry services.';

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
    _discountMinimumEntries.dispose();
    _discountMaximumEntries.dispose();
    _discountRequiredShows.dispose();

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
          .select('is_locked,finalized_at,online_payment_fee_mode')
          .eq('id', widget.showId)
          .single();

      _isLocked = show['is_locked'] == true;
      _isFinalized = (show['finalized_at'] ?? '').toString().trim().isNotEmpty;
      final loadedOnlinePaymentFeeMode =
          (show['online_payment_fee_mode'] ?? 'club_absorbs').toString();
      _onlinePaymentFeeMode = loadedOnlinePaymentFeeMode == 'pass_to_exhibitor'
          ? 'pass_to_exhibitor'
          : 'club_absorbs';

      final feeRow = await StripeConnectService.supabase
          .from('show_fee_settings')
          .select(
            'currency,'
            'multi_show_discount_enabled,'
            'multi_show_discount_type,'
            'multi_show_discount_value,'
            'multi_show_discount_basis,'
            'multi_show_discount_scope,'
            'multi_show_discount_min_entries,'
            'multi_show_discount_max_entries,'
            'multi_show_discount_required_shows',
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

      final sectionFeeRows = (sectionFeeRes as List)
          .cast<Map<String, dynamic>>();
      final feeBySectionId = {
        for (final row in sectionFeeRows) row['section_id'].toString(): row,
      };

      _discountEnabled = feeRow?['multi_show_discount_enabled'] == true;
      _discountType = (feeRow?['multi_show_discount_type'] ?? 'amount')
          .toString();
      _discountValue.text = (feeRow?['multi_show_discount_value'] ?? 0)
          .toString();
      _discountBasis = (feeRow?['multi_show_discount_basis'] ?? 'each_show')
          .toString();
      _discountScope = (feeRow?['multi_show_discount_scope'] ?? 'both')
          .toString();
      _discountMinimumEntries.text =
          (feeRow?['multi_show_discount_min_entries'] ?? 12).toString();
      _discountMaximumEntries.text =
          feeRow?['multi_show_discount_max_entries'] == null
          ? ''
          : feeRow!['multi_show_discount_max_entries'].toString();
      _discountRequiredShows.text =
          (feeRow?['multi_show_discount_required_shows'] ?? 3).toString();

      for (final section in sections) {
        final sectionId = section['id'].toString();
        final row = feeBySectionId[sectionId];

        _entryControllerFor(sectionId).text = (row?['fee_per_entry'] ?? 0)
            .toString();

        _showControllerFor(sectionId).text = row?['fee_per_show'] == null
            ? ''
            : row!['fee_per_show'].toString();

        _furControllerFor(sectionId).text = (row?['fur_fee'] ?? 0).toString();
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

  int? _parsePositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  int? _parseOptionalPositiveInt(String value) {
    if (value.trim().isEmpty) return null;
    return _parsePositiveInt(value);
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
    if (_isReadOnly) {
      setState(
        () => _msg = _isFinalized
            ? 'This show has been finalized. Fees and payment settings can no longer be changed.'
            : 'This show is locked. Fees and payment settings can no longer be changed.',
      );
      return false;
    }
    for (final section in _sections) {
      final sectionId = section['id'].toString();
      final sectionName = _sectionLabel(section);

      final perEntry = _parseMoney(_entryControllerFor(sectionId).text);
      if (perEntry == null) {
        setState(
          () => _msg = '$sectionName fee per entry must be 0 or greater.',
        );
        return false;
      }

      final feePerShowText = _showControllerFor(sectionId).text.trim();
      if (feePerShowText.isNotEmpty) {
        final perShow = _parseMoney(feePerShowText);
        if (perShow == null) {
          setState(
            () => _msg =
                '$sectionName fee per show must be 0 or greater, or left blank.',
          );
          return false;
        }
      }

      final furFee = _parseMoney(_furControllerFor(sectionId).text);
      if (furFee == null) {
        setState(
          () => _msg = '$sectionName Fur/Wool fee must be 0 or greater.',
        );
        return false;
      }
    }

    final disc = _parseMoney(_discountValue.text);
    if (disc == null) {
      setState(
        () => _msg = _discountType == 'fixed_rate'
            ? 'Discounted entry rate must be 0 or greater.'
            : 'Discount must be 0 or greater.',
      );
      return false;
    }

    if (_discountEnabled && _discountType == 'percent' && disc > 100) {
      setState(() => _msg = 'Percent discount cannot exceed 100.');
      return false;
    }

    if (_discountEnabled) {
      final minimumEntries = _parsePositiveInt(_discountMinimumEntries.text);
      if (minimumEntries == null) {
        setState(
          () =>
              _msg = 'Minimum entries must be a whole number of 1 or greater.',
        );
        return false;
      }

      final maximumEntries = _parseOptionalPositiveInt(
        _discountMaximumEntries.text,
      );
      if (_discountMaximumEntries.text.trim().isNotEmpty &&
          maximumEntries == null) {
        setState(
          () => _msg =
              'Maximum entries must be a whole number of 1 or greater, or left blank.',
        );
        return false;
      }

      if (maximumEntries != null && maximumEntries < minimumEntries) {
        setState(
          () => _msg = 'Maximum entries cannot be less than minimum entries.',
        );
        return false;
      }

      final eligibleSectionCount = _sections.where((section) {
        if (_discountScope == 'both') return true;
        final kind = (section['kind'] ?? '').toString().trim().toLowerCase();
        return kind == _discountScope;
      }).length;

      if (eligibleSectionCount == 0) {
        setState(
          () => _msg = _discountScope == 'open'
              ? 'There are no enabled Open show sections for this discount.'
              : 'There are no enabled Youth show sections for this discount.',
        );
        return false;
      }

      final requiredShows = _parsePositiveInt(_discountRequiredShows.text);
      if (requiredShows == null) {
        setState(
          () => _msg =
              'Minimum number of shows must be a whole number of 1 or greater.',
        );
        return false;
      }

      if (requiredShows > eligibleSectionCount) {
        final scopeLabel = _discountScope == 'both'
            ? 'Open and Youth'
            : _discountScope == 'open'
            ? 'Open'
            : 'Youth';
        setState(
          () => _msg =
              'Minimum number of shows cannot exceed the number of enabled $scopeLabel sections ($eligibleSectionCount).',
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _connectStripe() async {
    if (_isReadOnly) {
      setState(() {
        _msg = _isFinalized
            ? 'This show has been finalized. Stripe setup can no longer be changed.'
            : 'This show is locked. Stripe setup can no longer be changed.';
      });
      return;
    }
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
    if (_isReadOnly) {
      setState(() {
        _msg = _isFinalized
            ? 'This show has been finalized. Stripe status is view-only.'
            : 'This show is locked. Stripe status is view-only.';
      });
      return;
    }
    if (mounted) {
      setState(() {
        _loadingStripeStatus = true;
        _msg = null;
      });
    }

    try {
      await StripeConnectService.refreshAccountStatus(widget.showId);
      await _loadStripeStatus(showErrorInBanner: true);

      if (!mounted) return;
      setState(() {
        _msg = 'Stripe status refreshed from Stripe.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStripeStatus = false;
        _msg = 'Stripe status refresh failed: $e';
      });
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;

    setState(() {
      _saving = true;
      _msg = null;
    });

    try {
      await ShowLockService.assertShowUnlocked(widget.showId);
      await StripeConnectService.supabase
          .from('shows')
          .update({
            'online_payment_fee_mode': _onlinePaymentFeeMode,
            'online_payment_fee_label': 'Online Payment Fee',
            'online_payment_fee_description': _onlinePaymentFeeDisclosure,
            'online_payment_provider': 'stripe',
            'online_payment_fee_updated_at': DateTime.now()
                .toUtc()
                .toIso8601String(),
            'online_payment_fee_updated_by':
                StripeConnectService.supabase.auth.currentUser?.id,
          })
          .eq('id', widget.showId);
      await StripeConnectService.supabase.from('show_fee_settings').upsert({
        'show_id': widget.showId,
        'multi_show_discount_enabled': _discountEnabled,
        'multi_show_discount_type': _discountType,
        'multi_show_discount_value': double.parse(_discountValue.text.trim()),
        'multi_show_discount_basis': _discountBasis,
        'multi_show_discount_scope': _discountScope,
        'multi_show_discount_min_entries': _discountEnabled
            ? int.parse(_discountMinimumEntries.text.trim())
            : null,
        'multi_show_discount_max_entries':
            _discountEnabled && _discountMaximumEntries.text.trim().isNotEmpty
            ? int.parse(_discountMaximumEntries.text.trim())
            : null,
        'multi_show_discount_required_shows': _discountEnabled
            ? int.parse(_discountRequiredShows.text.trim())
            : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final sectionRows = _sections.map((section) {
        final sectionId = section['id'].toString();

        return {
          'section_id': sectionId,
          'fee_per_entry': double.parse(
            _entryControllerFor(sectionId).text.trim(),
          ),
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
    return AppTheme.surfaceTextScope(
      context,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 12,
            ),
          ],
        ),
        child: Builder(
          builder: (context) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: AppColors.navy),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 14),
                ...children,
              ],
            );
          },
        ),
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

  Widget _buildStripeStatusPill({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
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
      return _section('Entry Fees', const [
        Text('No enabled show sections found.'),
      ], icon: Icons.confirmation_number_outlined);
    }

    return _section('Entry Fees by Show Section', [
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
            border: Border.all(color: Colors.black.withValues(alpha: .06)),
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
                        if (i != fields.length - 1) const SizedBox(width: 12),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        );
      }),
    ], icon: Icons.attach_money);
  }

  Widget _buildDiscountSection() {
    return _section('Discounts', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Enable entry volume discount',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Offer a discounted entry price when an exhibitor meets the required entry count per show or across multiple show sections.',
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
            final stack = constraints.maxWidth < 620;

            final basisField = DropdownButtonFormField<String>(
              initialValue: _discountBasis,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'each_show',
                  child: Text(
                    'Minimum entries per show',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'cumulative',
                  child: Text(
                    'Cumulative entries across shows',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (_saving || _isReadOnly)
                  ? null
                  : (v) => setState(() => _discountBasis = v ?? 'each_show'),
              decoration: const InputDecoration(
                labelText: 'How exhibitors qualify',
                border: OutlineInputBorder(),
              ),
            );

            final scopeField = DropdownButtonFormField<String>(
              initialValue: _discountScope,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'both', child: Text('Open and Youth')),
                DropdownMenuItem(value: 'open', child: Text('Open only')),
                DropdownMenuItem(value: 'youth', child: Text('Youth only')),
              ],
              onChanged: (_saving || _isReadOnly)
                  ? null
                  : (v) => setState(() => _discountScope = v ?? 'both'),
              decoration: const InputDecoration(
                labelText: 'Applies to',
                border: OutlineInputBorder(),
              ),
            );

            if (stack) {
              return Column(
                children: [basisField, const SizedBox(height: 12), scopeField],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: basisField),
                const SizedBox(width: 12),
                Expanded(child: scopeField),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 620;

            final fields = [
              TextField(
                controller: _discountMinimumEntries,
                enabled: !_saving && !_isReadOnly,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _discountBasis == 'each_show'
                      ? 'Minimum entries per show'
                      : 'Minimum total entries',
                  helperText: _discountBasis == 'each_show'
                      ? 'Example: 12 animals in a show'
                      : 'Example: 36 entries across 3 shows',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _discountMaximumEntries,
                enabled: !_saving && !_isReadOnly,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: _discountBasis == 'each_show'
                      ? 'Maximum entries per show'
                      : 'Maximum entries',
                  helperText: 'Optional; leave blank for no maximum',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _discountRequiredShows,
                enabled: !_saving && !_isReadOnly,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Minimum number of shows',
                  helperText: 'Example: 3 for a triple show',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
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
                  if (i != fields.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 520;

            final typeField = DropdownButtonFormField<String>(
              initialValue: _discountType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: 'fixed_rate',
                  child: Text(
                    'Fixed discounted rate per entry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'amount',
                  child: Text(
                    'Amount off each entry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'percent',
                  child: Text(
                    'Percent off each entry',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (_saving || _isReadOnly)
                  ? null
                  : (v) => setState(() => _discountType = v ?? 'fixed_rate'),
              decoration: const InputDecoration(
                labelText: 'Discount pricing method',
                border: OutlineInputBorder(),
              ),
            );

            final valueField = TextField(
              controller: _discountValue,
              enabled: !_saving && !_isReadOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _discountType == 'fixed_rate'
                    ? 'Discounted rate per entry'
                    : 'Discount value',
                prefixText: _discountType == 'percent' ? null : '\$ ',
                suffixText: _discountType == 'percent' ? '%' : null,
                helperText: _discountType == 'fixed_rate'
                    ? 'Example: charge \$3.00 per qualifying entry'
                    : null,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            );

            if (stack) {
              return Column(
                children: [typeField, const SizedBox(height: 12), valueField],
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
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.navy.withValues(alpha: .10)),
          ),
          child: Text(
            _discountBasis == 'each_show'
                ? 'Example: require 12 or more entries in each of 3 ${_discountScope == 'both'
                      ? 'Open or Youth'
                      : _discountScope == 'open'
                      ? 'Open'
                      : 'Youth'} shows, then apply the discount to qualifying entries.'
                : 'Example: require 36 total entries across 3 ${_discountScope == 'both'
                      ? 'Open or Youth'
                      : _discountScope == 'open'
                      ? 'Open'
                      : 'Youth'} shows, then apply the selected discount to qualifying entries.',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ], icon: Icons.discount_outlined);
  }

  Widget _buildOnlinePaymentFeeSection() {
    return _section('Online Payment Fee', [
      Text(
        'Choose how online payment costs are handled for this show.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      RadioGroup<String>(
        groupValue: _onlinePaymentFeeMode,
        onChanged: (value) {
          if (_saving || _isReadOnly) return;
          setState(() => _onlinePaymentFeeMode = value ?? 'club_absorbs');
        },
        child: Opacity(
          opacity: (_saving || _isReadOnly) ? .65 : 1,
          child: Column(
            children: const [
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'club_absorbs',
                title: Text(
                  'Club absorbs fees',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'The exhibitor pays only their show-defined fees. Online payment costs are deducted from the club payout.',
                ),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: 'pass_to_exhibitor',
                title: Text(
                  'Pass Online Payment Fee to exhibitors',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'The exhibitor pays an added Online Payment Fee at checkout. This fee helps cover payment processing costs, payment provider charges, and RingMaster online entry services.',
                ),
              ),
            ],
          ),
        ),
      ),
      if (_onlinePaymentFeeMode == 'pass_to_exhibitor') ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.navy.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.navy.withValues(alpha: .10)),
          ),
          child: const Text(
            _onlinePaymentFeeDisclosure,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ], icon: Icons.receipt_long_outlined);
  }

  Widget _buildStripeSection() {
    final status = (_stripeStatus?['status'] ?? 'not_connected').toString();
    final color = _statusColor(status);
    final label = _statusLabel(status);

    final showPaymentAccount =
        _stripeStatus?['show_payment_account'] as Map<String, dynamic>?;
    final providerAccountId = (showPaymentAccount?['provider_account_id'] ?? '')
        .toString();

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
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.navy.withValues(alpha: .10)),
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
          children: [_buildStripeStatusPill(text: label, color: color)],
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
              color: Colors.orange.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: .20)),
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
            onPressed:
                (_saving ||
                    _isReadOnly ||
                    _connectingStripe ||
                    _loadingStripeStatus)
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
            onPressed:
                (_saving ||
                    _isReadOnly ||
                    _connectingStripe ||
                    _loadingStripeStatus)
                ? null
                : _refreshStripeStatus,
          );

          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [primary, const SizedBox(height: 10), refresh],
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
    ], icon: Icons.payments_outlined);
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
          gradient: AppGradients.page,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/RingMaster_One_Show_Transparent.png',
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
                  color: AppColors.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: AppTheme.gradientTextScope(
                  context,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.all(20),
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
                                    border: Border.all(
                                      color: Colors.amber.shade300,
                                    ),
                                  ),
                                  child: Text(
                                    _isFinalized
                                        ? 'This show has been finalized. Fees and payment settings are view-only.'
                                        : 'This show is locked. Fees and payment settings are view-only.',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              if (_msg != null)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: success
                                        ? Colors.green.withValues(alpha: .08)
                                        : Colors.red.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: success
                                          ? Colors.green.withValues(alpha: .25)
                                          : Colors.red.withValues(alpha: .25),
                                    ),
                                  ),
                                  child: Text(
                                    _msg!,
                                    style: TextStyle(
                                      color: success
                                          ? Colors.green.shade700
                                          : Colors.red,
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
                                      _buildOnlinePaymentFeeSection(),
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
                                        backgroundColor:
                                            AppColors.primaryButton,
                                        foregroundColor:
                                            AppColors.primaryButtonText,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                      ),
                                      onPressed:
                                          (_saving ||
                                              _isReadOnly ||
                                              _connectingStripe)
                                          ? null
                                          : _save,
                                      icon: const Icon(Icons.save_outlined),
                                      label: Text(
                                        _saving
                                            ? 'Saving…'
                                            : _isReadOnly
                                            ? 'View Only'
                                            : 'Save Changes',
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
            ),
          ],
        ),
      ),
    );
  }
}
