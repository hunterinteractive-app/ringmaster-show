// lib/screens/cart_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import '../utils/date_time_utils.dart';
import '../services/app_session.dart';
import '../services/stripe_connect_service.dart';

import 'my_entries_screen.dart';

final supabase = Supabase.instance.client;

class CartScreen extends StatefulWidget {
  final String cartId;
  final String showId;
  final String showName;

  const CartScreen({
    super.key,
    required this.cartId,
    required this.showId,
    required this.showName,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _loading = true;
  bool _confirming = false;
  bool _payingOnline = false;
  bool _handledStripeReturn = false;
  String? _msg;

  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _show;
  Map<String, Map<String, dynamic>> _sectionById = {};
  Map<String, dynamic>? _feeSettings;
  Map<String, Map<String, dynamic>> _sectionFeeBySectionId = {};
  Map<String, dynamic>? _stripeStatus;

  final Map<String, String> _exhibitorLabelById = {};

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted) {
        _handleStripeReturnIfPresent();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select('id,name,entry_close_at,entry_open_at,start_date')
          .eq('id', widget.showId)
          .single();

      final fee = await supabase
          .from('show_fee_settings')
          .select(
            'show_id,currency,fee_per_entry,fee_per_show,fur_fee,'
            'multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value',
          )
          .eq('show_id', widget.showId)
          .maybeSingle();

      final sectionsRes = await supabase
          .from('show_sections')
          .select('id,display_name,kind,letter,sort_order')
          .eq('show_id', widget.showId)
          .order('sort_order');

      final sections = (sectionsRes as List).cast<Map<String, dynamic>>();
      final sectionIds = sections
          .map((s) => s['id'].toString())
          .where((id) => id.isNotEmpty)
          .toList();

      final sectionFeesRes = sectionIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await supabase
              .from('show_section_fee_settings')
              .select(
                'section_id,fee_per_entry,fee_per_show,fur_fee,updated_at',
              )
              .inFilter('section_id', sectionIds);

      final sectionFees =
          (sectionFeesRes as List).cast<Map<String, dynamic>>();

      final items = await supabase
          .from('entry_cart_items')
          .select(
            'id,exhibitor_id,section_id,animal_id,species,breed,variety,fur_variety,sex,tattoo,animal_name,class_name,created_at,is_fur',
          )
          .eq('cart_id', widget.cartId)
          .order('created_at');

      Map<String, dynamic>? stripeStatus;
      try {
        stripeStatus =
            await StripeConnectService.getAccountStatus(widget.showId);
      } catch (_) {
        stripeStatus = await _loadStripeStatusFallback();
      }

      final parsedSections = {
        for (final s in sections) s['id'].toString(): s,
      };

      final parsedSectionFees = {
        for (final row in sectionFees) row['section_id'].toString(): row,
      };

      final parsedItems = (items as List).cast<Map<String, dynamic>>();

      await _loadExhibitorLabelsForCart(parsedItems);

      if (!mounted) return;
      setState(() {
        _show = show;
        _feeSettings = fee;
        _sectionById = parsedSections;
        _items = parsedItems;
        _stripeStatus = stripeStatus;
        _sectionFeeBySectionId = parsedSectionFees;
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

  Future<Map<String, dynamic>?> _loadStripeStatusFallback() async {
    final row = await supabase
        .from('show_payment_account_links')
        .select(
          'id,show_id,provider,stripe_account_id,charges_enabled,payouts_enabled,details_submitted,account_status',
        )
        .eq('show_id', widget.showId)
        .eq('provider', 'stripe')
        .maybeSingle();

    if (row == null) return null;

    final stripeAccountId = (row['stripe_account_id'] ?? '').toString().trim();
    if (stripeAccountId.isEmpty) return null;

    final chargesEnabled = row['charges_enabled'] == true;
    final payoutsEnabled = row['payouts_enabled'] == true;
    final detailsSubmitted = row['details_submitted'] == true;
    final accountStatus = (row['account_status'] ?? '').toString().trim();

    return {
      'ok': true,
      'status': accountStatus.isNotEmpty ? accountStatus : 'connected',
      'charges_enabled': chargesEnabled,
      'payouts_enabled': payoutsEnabled,
      'details_submitted': detailsSubmitted,
      'show_payment_account': row,
    };
  }

  Future<void> _loadExhibitorLabelsForCart(
    List<Map<String, dynamic>> items,
  ) async {
    _exhibitorLabelById.clear();

    final ids = <String>{};
    for (final it in items) {
      final id = it['exhibitor_id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }

    if (ids.isEmpty) return;

    final rows = await supabase
        .from('exhibitors')
        .select('id,showing_name,display_name,first_name,last_name')
        .inFilter('id', ids.toList());

    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final id = r['id'].toString();
      final showingName = (r['showing_name'] ?? '').toString().trim();
      final displayName = (r['display_name'] ?? '').toString().trim();
      final fn = (r['first_name'] ?? '').toString().trim();
      final ln = (r['last_name'] ?? '').toString().trim();

      final label = showingName.isNotEmpty
          ? showingName
          : (displayName.isNotEmpty
              ? displayName
              : [fn, ln].where((x) => x.isNotEmpty).join(' ').trim());

      _exhibitorLabelById[id] = label.isEmpty ? 'Exhibitor' : label;
    }
  }

  DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  bool _deadlinePassed() {
    final closeAt = _parseTs(_show?['entry_close_at']);
    if (closeAt == null) return false;
    return DateTime.now().isAfter(closeAt.toLocal());
  }

  double _asDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return fallback;
    return double.tryParse(s) ?? fallback;
  }

  String _currencySymbol(String? currency) {
    final c = (currency ?? 'USD').toUpperCase();
    if (c == 'USD') return r'$';
    if (c == 'CAD') return r'$';
    if (c == 'EUR') return '€';
    if (c == 'GBP') return '£';
    return r'$';
  }

  String _money(double v, {String? currency}) {
    final sym = _currencySymbol(currency);
    return '$sym${v.toStringAsFixed(2)}';
  }

  String? _buildFurDisplay(Map<String, dynamic> it) {
    if (it['is_fur'] != true) return null;

    final furVariety = (it['fur_variety'] ?? '').toString().trim();
    if (furVariety.isNotEmpty) {
      return 'Fur/Wool: $furVariety';
    }

    return 'Fur/Wool: Yes';
  }

  String _buildClassDisplay(Map<String, dynamic> it) {
    final className = (it['class_name'] ?? '').toString().trim();

    if (className.isEmpty) {
      return 'Class: Needs Validation ⚠️';
    }

    return 'Projected Class: $className';
  }

  bool get _stripeHasAccount {
    final account = _stripeStatus?['show_payment_account'];
    final nestedStripeAccountId = account is Map
        ? (account['stripe_account_id'] ?? account['provider_account_id'] ?? '')
            .toString()
            .trim()
        : '';

    final topLevelStripeAccountId = (_stripeStatus?['stripe_account_id'] ??
            _stripeStatus?['provider_account_id'] ??
            '')
        .toString()
        .trim();

    return nestedStripeAccountId.isNotEmpty || topLevelStripeAccountId.isNotEmpty;
  }

  bool get _stripeReady {
    if (!_stripeHasAccount) return false;

    final status = (_stripeStatus?['status'] ?? '').toString().toLowerCase().trim();
    final accountStatus = (_stripeStatus?['account_status'] ??
            (_stripeStatus?['show_payment_account'] is Map
                ? (_stripeStatus!['show_payment_account'] as Map)['account_status']
                : null) ??
            '')
        .toString()
        .toLowerCase()
        .trim();

    final isRestricted = status == 'restricted' ||
        accountStatus == 'restricted' ||
        status == 'incomplete' ||
        accountStatus == 'incomplete' ||
        status == 'not_ready' ||
        accountStatus == 'not_ready';

    if (isRestricted) return false;

    return _stripeStatus?['charges_enabled'] == true &&
        _stripeStatus?['payouts_enabled'] == true &&
        _stripeStatus?['details_submitted'] == true;
  }


  bool get _canPayOnline {
    return !_loading &&
        !_payingOnline &&
        !_confirming &&
        !AppSession.isSupportMode &&
        !_deadlinePassed() &&
        _items.isNotEmpty &&
        _stripeReady;
  }

  Map<String, dynamic> _calculateFeesForItems(
    List<Map<String, dynamic>> items,
  ) {
    final currency = (_feeSettings?['currency'] ?? 'USD').toString();

    final discountEnabled =
        _feeSettings?['multi_show_discount_enabled'] == true;
    final discountType = (_feeSettings?['multi_show_discount_type'] ?? '')
        .toString()
        .toLowerCase();
    final discountValue =
        _asDouble(_feeSettings?['multi_show_discount_value']);

    double entriesSubtotal = 0.0;
    double furSubtotal = 0.0;
    double showFeeSubtotal = 0.0;

    int furCount = 0;

    final Map<String, int> perAnimalCounts = {};
    final Set<String> chargedShowFeeSectionIds = {};

    for (final it in items) {
      final sectionId = (it['section_id'] ?? '').toString();
      final sectionFee = _sectionFeeBySectionId[sectionId];

      final feePerEntry = _asDouble(sectionFee?['fee_per_entry']);
      final feePerShow = _asDouble(sectionFee?['fee_per_show']);
      final furFee = _asDouble(sectionFee?['fur_fee']);

      entriesSubtotal += feePerEntry;

      if (it['is_fur'] == true) {
        furSubtotal += furFee;
        furCount += 1;
      }

      if (sectionId.isNotEmpty &&
          !chargedShowFeeSectionIds.contains(sectionId) &&
          feePerShow > 0) {
        chargedShowFeeSectionIds.add(sectionId);
        showFeeSubtotal += feePerShow;
      }

      final animalId = it['animal_id']?.toString();
      if (animalId != null && animalId.isNotEmpty) {
        perAnimalCounts[animalId] = (perAnimalCounts[animalId] ?? 0) + 1;
      }
    }

    int additionalEntries = 0;
    perAnimalCounts.forEach((_, count) {
      if (count > 1) additionalEntries += (count - 1);
    });

    double discountAmount = 0.0;
    if (discountEnabled && additionalEntries > 0) {
      double averageEntryFee = 0.0;
      if (items.isNotEmpty) {
        averageEntryFee = entriesSubtotal / items.length;
      }

      if (discountType == 'percent') {
        final pct =
            (discountValue <= 1.0) ? discountValue : (discountValue / 100.0);
        discountAmount = (averageEntryFee * additionalEntries) * pct;
      } else if (discountType == 'amount') {
        discountAmount = additionalEntries * discountValue;
      }

      final maxDiscount = averageEntryFee * additionalEntries;
      if (discountAmount > maxDiscount) discountAmount = maxDiscount;
      if (discountAmount < 0) discountAmount = 0;
    }

    final total =
        (entriesSubtotal + furSubtotal + showFeeSubtotal) - discountAmount;

    return {
      'currency': currency,
      'entry_count': items.length,
      'fur_count': furCount,
      'entries_subtotal': entriesSubtotal,
      'fur_subtotal': furSubtotal,
      'show_fee': showFeeSubtotal,
      'additional_entries': additionalEntries,
      'discount_enabled': discountEnabled,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_amount': discountAmount,
      'total': total < 0 ? 0.0 : total,
    };
  }

  Map<String, List<Map<String, dynamic>>> _groupItemsByExhibitor() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final it in _items) {
      final exhibitorId = it['exhibitor_id']?.toString().trim();
      final key = (exhibitorId == null || exhibitorId.isEmpty)
          ? '__unassigned__'
          : exhibitorId;
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(it);
    }

    final keys = grouped.keys.toList();
    keys.sort((a, b) {
      if (a == '__unassigned__') return 1;
      if (b == '__unassigned__') return -1;
      final la = (_exhibitorLabelById[a] ?? a).toLowerCase();
      final lb = (_exhibitorLabelById[b] ?? b).toLowerCase();
      return la.compareTo(lb);
    });

    final ordered = <String, List<Map<String, dynamic>>>{};
    for (final k in keys) {
      ordered[k] = grouped[k]!;
    }
    return ordered;
  }

  bool _isCommercialEntry(Map<String, dynamic> item) {
    final breed = (item['breed'] ?? '').toString().trim().toLowerCase();
    return breed == 'commercial';
  }

  bool _isMeatPenEntry(Map<String, dynamic> item) {
    final className =
        (item['class_name'] ?? '').toString().trim().toLowerCase();
    final variety = (item['variety'] ?? '').toString().trim().toLowerCase();
    return className == 'meat pen' || variety == 'meat pen';
  }

  String _cartItemTitle(Map<String, dynamic> item, String sectionName) {
    final tattoo = (item['tattoo'] ?? '').toString().trim();
    final animalName = (item['animal_name'] ?? '').toString().trim();
    final animalId = (item['animal_id'] ?? '').toString().trim();
    final furVariety = (item['fur_variety'] ?? '').toString().trim();

    String animalLabel() {
      if (animalName.isNotEmpty && tattoo.isNotEmpty) {
        return '$animalName • $tattoo';
      }
      if (animalName.isNotEmpty) return animalName;
      if (tattoo.isNotEmpty) return tattoo;
      return animalId;
    }

    if (_isMeatPenEntry(item)) {
      return '$sectionName — Meat Pen';
    }

    if (_isCommercialEntry(item)) {
      final label = (item['class_name'] ?? item['variety'] ?? 'Commercial')
          .toString()
          .trim();
      final idLabel = animalLabel();

      return idLabel.isNotEmpty
          ? '$sectionName — $label ($idLabel)'
          : '$sectionName — $label';
    }

    final baseTitle = '$sectionName — ${animalLabel()}';

    if (item['is_fur'] == true && furVariety.isNotEmpty) {
      return '$baseTitle ($furVariety)';
    }

    return baseTitle;
  }

  String _cartItemSubtitle(Map<String, dynamic> item) {
    if (_isMeatPenEntry(item)) {
      final tattoo = (item['tattoo'] ?? '').toString().trim();
      return tattoo.isEmpty
          ? 'Commercial • Meat Pen'
          : 'Commercial • Meat Pen\nTattoos: $tattoo';
    }

    if (_isCommercialEntry(item)) {
      final label = (item['class_name'] ?? item['variety'] ?? 'Commercial')
          .toString()
          .trim();
      final sex = (item['sex'] ?? '').toString().trim();

      if (sex.isNotEmpty) {
        return 'Commercial • $label • $sex';
      }
      return 'Commercial • $label';
    }

    final animalLabel =
        '${(item['breed'] ?? '').toString()} • ${(item['variety'] ?? '').toString()} • ${(item['sex'] ?? '').toString()}';

    final furDisplay = _buildFurDisplay(item);

    if (furDisplay != null) {
      return '$animalLabel\n${_buildClassDisplay(item)}\n$furDisplay';
    }

    return '$animalLabel\n${_buildClassDisplay(item)}';
  }

  bool _cartItemIsThreeLine(Map<String, dynamic> item) {
    if (_isMeatPenEntry(item)) return true;
    if (_isCommercialEntry(item)) return false;
    return true;
  }

  Future<void> _removeItem(String itemId) async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Removing cart items is disabled while viewing in support mode.';
      });
      return;
    }
    try {
      await supabase.from('entry_cart_items').delete().eq('id', itemId);
      await _load();
    } catch (e) {
      setState(() => _msg = 'Remove failed: $e');
    }
  }

  void _handleStripeReturnIfPresent() {
    if (_handledStripeReturn) return;
    _handledStripeReturn = true;

    final uri = Uri.base;
    final returnCartId = (uri.queryParameters['cart_id'] ?? '').trim();
    final stripeStatus =
        (uri.queryParameters['stripe'] ?? '').trim().toLowerCase();

    if (returnCartId.isEmpty || returnCartId != widget.cartId) {
      return;
    }

    if (stripeStatus == 'success') {
      setState(() {
        _msg = null;
      });

      Future.delayed(const Duration(milliseconds: 800), () async {
        if (!mounted) return;

        await _load();
        if (!mounted) return;

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Payment Successful'),
            content: const Text(
              'Your payment was received and your entries were submitted successfully.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, true);
                },
                child: const Text('Back to Show'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MyEntriesScreen(),
                    ),
                  );
                },
                child: const Text('View My Entries'),
              ),
            ],
          ),
        );
      });
    } else if (stripeStatus == 'cancel') {
      setState(() {
        _msg = 'Stripe Checkout was canceled. Your cart is still available.';
      });
    }
  }

  Future<void> _payOnline() async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Online payment is disabled while viewing in support mode.';
      });
      return;
    }
    if (_items.isEmpty) {
      setState(() => _msg = 'Your cart is empty. If you are looking for completed entries please return to the upcoming shows tab and select Entries.');
      return;
    }

    if (_deadlinePassed()) {
      setState(
        () => _msg = 'Entry deadline has passed. You can’t pay for this cart.',
      );
      return;
    }

    final hasUnassigned = _items.any((it) {
      final ex = it['exhibitor_id']?.toString().trim();
      return ex == null || ex.isEmpty;
    });

    if (hasUnassigned) {
      setState(() {
        _msg =
            'One or more cart items are missing an exhibitor. Please fix before paying online.';
      });
      return;
    }

    if (!_stripeReady) {
      setState(() {
        _msg = _stripeHasAccount
            ? 'Online payment is not available yet. The club’s Stripe setup is incomplete.'
            : 'Online payment is not available for this show yet. The club has not connected Stripe.';
      });
      return;
    }

    setState(() {
      _payingOnline = true;
      _msg = null;
    });

    try {
      final checkoutUrl =
          await StripeConnectService.createCheckoutSession(widget.cartId);

      final uri = Uri.parse(checkoutUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );

      if (!launched) {
        throw Exception('Could not open Stripe Checkout.');
      }

      if (!mounted) return;
      setState(() {
        _msg =
            'Stripe Checkout opened. After payment, return here and use Reload if needed.';
      });
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString();
      final friendlyMessage = errorText.contains('not yet ready to accept charges') ||
              errorText.contains('Stripe account is not yet ready')
          ? 'Online payment is not available yet. The club’s Stripe setup is incomplete.'
          : 'Online payment failed: $e';

      setState(() => _msg = friendlyMessage);
    } finally {
      if (mounted) {
        setState(() => _payingOnline = false);
      }
    }
  }

  Future<void> _confirmDayOf() async {
    if (AppSession.isSupportMode) {
      setState(() {
        _msg = 'Submitting entries is disabled while viewing in support mode.';
      });
      return;
    }
    if (_items.isEmpty) {
      setState(() => _msg = 'Your cart is empty.');
      return;
    }
    if (_deadlinePassed()) {
      setState(
        () => _msg = 'Entry deadline has passed. You can’t submit this cart.',
      );
      return;
    }

    final hasUnassigned = _items.any((it) {
      final ex = it['exhibitor_id']?.toString().trim();
      return ex == null || ex.isEmpty;
    });
    if (hasUnassigned) {
      setState(() {
        _msg =
            'One or more cart items are missing an exhibitor. Please fix before confirming.';
      });
      return;
    }

    setState(() {
      _confirming = true;
      _msg = null;
    });

    try {
      final res = await supabase.rpc(
        'commit_entry_cart_day_of',
        params: {'p_cart_id': widget.cartId},
      );

      final insertedCount = (res as num).toInt();

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Entries Received'),
          content: Text(
            insertedCount == 1
                ? 'We have received your 1 entry. To review it, please view the Entries tab.'
                : 'We have received your $insertedCount entries. To review them, please view the Entries tab.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _msg = 'Confirm failed: $e');
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  String _buildExhibitorFeeLine({
    required List<Map<String, dynamic>> exhibitorItems,
    required String currency,
  }) {
    final f = _calculateFeesForItems(exhibitorItems);

    final entriesSubtotal = f['entries_subtotal'] as double;
    final furSubtotal = f['fur_subtotal'] as double;
    final showFee = f['show_fee'] as double;
    final discountAmount = f['discount_amount'] as double;
    final total = (entriesSubtotal + furSubtotal + showFee - discountAmount);
    final count = f['entry_count'] as int;
    final furCount = f['fur_count'] as int;

    final parts = <String>[
      '$count entries: ${_money(entriesSubtotal, currency: currency)}',
    ];

    if (furCount > 0) {
      parts.add(
        '$furCount Fur/Wool: ${_money(furSubtotal, currency: currency)}',
      );
    }

    if (showFee > 0) {
      parts.add('Show fees: ${_money(showFee, currency: currency)}');
    }

    if (discountAmount > 0) {
      parts.add('- ${_money(discountAmount, currency: currency)}');
    }

    parts.add('= ${_money(total, currency: currency)}');

    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final overallFee = _calculateFeesForItems(_items);
    final currency = overallFee['currency'] as String;
    final grouped = _groupItemsByExhibitor();
    final hasFeeConfig =
        _feeSettings != null && _sectionFeeBySectionId.isNotEmpty;

    return RingMasterPageShell(
      title: widget.showName,
      subtitle: 'Entry Cart',
      showBackButton: true,
      actions: [
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: (_confirming || _payingOnline) ? null : _load,
        ),
        IconButton(
          tooltip: 'My Entries',
          icon: const Icon(Icons.list_alt),
          onPressed: (_confirming || _payingOnline)
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyEntriesScreen(),
                    ),
                  );
                },
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (AppSession.isSupportMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Text(
                        'Support Mode — Cart is read-only. Remove, payment, and submit actions are disabled.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (_msg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withOpacity(.25),
                        ),
                      ),
                      child: Text(
                        _msg!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
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
                        Text(
                          _deadlinePassed()
                              ? 'Entry deadline: PASSED'
                              : 'Entry deadline: ${formatLocalDateTime(_show?['entry_close_at']?.toString())}',
                          style: TextStyle(
                            color:
                                _deadlinePassed() ? Colors.red : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Overall Fees',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        !hasFeeConfig
                            ? Text(
                                'Fee settings are incomplete for this show.',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${overallFee['entry_count']} entries = ${_money(overallFee['entries_subtotal'] as double, currency: currency)}',
                                  ),
                                  if ((overallFee['fur_count'] as int) > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '${overallFee['fur_count']} Fur/Wool add-ons = ${_money(overallFee['fur_subtotal'] as double, currency: currency)}',
                                      ),
                                    ),
                                  if ((overallFee['show_fee'] as double) > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Per-show fees: ${_money(overallFee['show_fee'] as double, currency: currency)}',
                                      ),
                                    ),
                                  if ((overallFee['discount_amount'] as double) >
                                      0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Multi-show discount (${overallFee['additional_entries']} additional entries): -${_money(overallFee['discount_amount'] as double, currency: currency)}',
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Total: ${_money(overallFee['total'] as double, currency: currency)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                        const SizedBox(height: 14),
                        Text(
                          _stripeReady
                              ? 'Online payment available'
                              : (_stripeHasAccount
                                  ? 'Online payment setup incomplete'
                                  : 'Online payment not yet available for this show'),
                          style: TextStyle(
                            color: _stripeReady
                                ? Colors.green
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(
                          child: Text(
                            'Your cart is empty.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final entry in grouped.entries) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(.04),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    _ExhibitorGroupHeader(
                                      exhibitorName: entry.key ==
                                              '__unassigned__'
                                          ? 'Unassigned Exhibitor'
                                          : (_exhibitorLabelById[entry.key] ??
                                              'Exhibitor'),
                                      feeSettingsExists: hasFeeConfig,
                                      feeLine: hasFeeConfig
                                          ? _buildExhibitorFeeLine(
                                              exhibitorItems: entry.value,
                                              currency: currency,
                                            )
                                          : null,
                                    ),
                                    const Divider(height: 1),
                                    ...entry.value.map((it) {
                                      final sectionId =
                                          it['section_id']?.toString() ?? '';
                                      final sec = _sectionById[sectionId];
                                      final secName =
                                          (sec?['display_name'] ?? 'Section')
                                              .toString();

                                      return ListTile(
                                        title: Text(
                                          _cartItemTitle(it, secName),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(_cartItemSubtitle(it)),
                                        isThreeLine:
                                            _cartItemIsThreeLine(it),
                                        trailing: IconButton(
                                          tooltip: 'Remove',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          onPressed: (AppSession.isSupportMode ||
                                                  _confirming ||
                                                  _payingOnline)
                                              ? null
                                              : () => _removeItem(
                                                    it['id'].toString(),
                                                  ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: _stripeReady
                        ? FilledButton.icon(
                            onPressed: _canPayOnline ? _payOnline : null,
                            icon: const Icon(Icons.credit_card),
                            label: Text(
                              _payingOnline
                                  ? 'Opening Checkout…'
                                  : 'Pay ${_money(overallFee['total'] as double, currency: currency)} Online',
                            ),
                          )
                        : FilledButton(
                            onPressed:
                                (AppSession.isSupportMode ||
                                        _confirming ||
                                        _deadlinePassed() ||
                                        _items.isEmpty)
                                    ? null
                                    : _confirmDayOf,
                            child: Text(
                              _confirming
                                  ? 'Confirming…'
                                  : 'Confirm Entries (Pay Day-of-Show)',
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ExhibitorGroupHeader extends StatelessWidget {
  final String exhibitorName;
  final bool feeSettingsExists;
  final String? feeLine;

  const _ExhibitorGroupHeader({
    required this.exhibitorName,
    required this.feeSettingsExists,
    required this.feeLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF11285A).withOpacity(.06),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exhibitorName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (feeSettingsExists && feeLine != null) ...[
            const SizedBox(height: 4),
            Text(
              feeLine!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}