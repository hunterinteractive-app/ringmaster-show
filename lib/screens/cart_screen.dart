// lib/screens/cart_screen.dart

import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';

import '../utils/date_time_utils.dart';
import '../services/app_session.dart';
import '../services/stripe_connect_service.dart';
import '../services/show_payment_configuration_service.dart';
import '../services/square_checkout_service.dart';

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
  String? _checkoutUrl;

  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _show;
  Map<String, Map<String, dynamic>> _sectionById = {};
  Map<String, dynamic>? _feeSettings;
  Map<String, Map<String, dynamic>> _sectionFeeBySectionId = {};
  Map<String, dynamic>? _stripeStatus;
  ShowPaymentConfiguration? _paymentConfiguration;
  String _selectedPaymentTiming = 'at_show';
  String? _selectedOnlineProvider;
  String? _squareClientAttemptKey;

  static const double _ringMasterPlatformFeePercent = 0.02;
  static const double _stripeProcessingFeePercent = 0.029;
  static const int _stripeProcessingFixedCents = 30;
  static const String _defaultOnlinePaymentFeeLabel = 'Online Payment Fee';
  static const String _defaultOnlinePaymentFeeDescription =
      'This show charges an Online Payment Fee for electronic payments. This fee helps cover payment processing costs, payment provider charges, and online entry services.';

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
      _checkoutUrl = null;
    });

    try {
      final show = await supabase
          .from('shows')
          .select(
            'id,name,entry_close_at,entry_open_at,start_date,'
            'online_payment_fee_mode,online_payment_fee_label,'
            'online_payment_fee_description,online_payment_provider',
          )
          .eq('id', widget.showId)
          .single();

      final fee = await supabase
          .from('show_fee_settings')
          .select(
            'show_id,currency,fee_per_entry,fee_per_show,fur_fee,'
            'multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value,'
            'multi_show_discount_basis,multi_show_discount_scope,'
            'multi_show_discount_min_entries,multi_show_discount_max_entries,'
            'multi_show_discount_required_shows',
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

      final sectionFees = (sectionFeesRes as List).cast<Map<String, dynamic>>();

      final items = await supabase
          .from('entry_cart_items')
          .select(
            'id,exhibitor_id,section_id,animal_id,species,breed,variety,fur_variety,sex,tattoo,animal_name,class_name,created_at,is_fur',
          )
          .eq('cart_id', widget.cartId)
          .order('created_at');

      final paymentConfiguration = await ShowPaymentConfigurationService.load(
        widget.showId,
      );
      Map<String, dynamic>? stripeStatus;
      try {
        stripeStatus = await StripeConnectService.getAccountStatus(
          widget.showId,
        );
      } catch (_) {
        stripeStatus = await _loadStripeStatusFallback();
      }

      final parsedSections = {for (final s in sections) s['id'].toString(): s};

      final parsedSectionFees = {
        for (final row in sectionFees) row['section_id'].toString(): row,
      };

      final parsedItems = (items as List).cast<Map<String, dynamic>>();

      await _loadExhibitorLabelsForCart(parsedItems);

      final readyProviders = paymentConfiguration.providers
          .where((provider) => provider.enabled && provider.ready)
          .map((provider) => provider.provider)
          .toList();
      final preferred = paymentConfiguration.defaultOnlineProvider;
      final selectedProvider = readyProviders.contains(preferred)
          ? preferred
          : (readyProviders.isEmpty ? null : readyProviders.first);
      final selectedTiming = paymentConfiguration.requireOnlinePayment
          ? 'online'
          : paymentConfiguration.allowAtShow
          ? 'at_show'
          : 'online';

      if (!mounted) return;
      setState(() {
        _show = show;
        _feeSettings = fee;
        _sectionById = parsedSections;
        _items = parsedItems;
        _stripeStatus = stripeStatus;
        _paymentConfiguration = paymentConfiguration;
        _selectedOnlineProvider = selectedProvider;
        _selectedPaymentTiming = selectedTiming;
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

  int _dollarsToCents(double amount) {
    if (!amount.isFinite || amount <= 0) return 0;
    return (amount * 100).round();
  }

  double _centsToDollars(int cents) {
    return cents <= 0 ? 0.0 : cents / 100.0;
  }

  bool get _passesOnlinePaymentFeeToExhibitor {
    return (_show?['online_payment_fee_mode'] ?? 'club_absorbs')
            .toString()
            .trim() ==
        'pass_to_exhibitor';
  }

  String get _onlinePaymentFeeLabel {
    final label = (_show?['online_payment_fee_label'] ?? '').toString().trim();
    return label.isEmpty ? _defaultOnlinePaymentFeeLabel : label;
  }

  String get _onlinePaymentFeeDescription {
    final description = (_show?['online_payment_fee_description'] ?? '')
        .toString()
        .trim();
    return description.isEmpty
        ? _defaultOnlinePaymentFeeDescription
        : description;
  }

  int _calculateOnlinePaymentFeeCentsFromBase(int baseAmountCents) {
    if (baseAmountCents <= 0) return 0;

    const combinedPercent =
        _ringMasterPlatformFeePercent + _stripeProcessingFeePercent;

    if (combinedPercent <= 0 && _stripeProcessingFixedCents <= 0) {
      return 0;
    }

    if (combinedPercent >= 1) return 0;

    var estimatedFeeCents =
        ((baseAmountCents + _stripeProcessingFixedCents) /
                    (1 - combinedPercent) -
                baseAmountCents)
            .ceil();

    if (estimatedFeeCents < 0) estimatedFeeCents = 0;

    for (var i = 0; i < 10; i++) {
      final grossAmountCents = baseAmountCents + estimatedFeeCents;
      final estimatedPlatformFeeCents =
          (grossAmountCents * _ringMasterPlatformFeePercent).round();
      final estimatedProcessingFeeCents =
          (grossAmountCents * _stripeProcessingFeePercent +
                  _stripeProcessingFixedCents)
              .ceil();
      final requiredFeeCents =
          estimatedPlatformFeeCents + estimatedProcessingFeeCents;

      if (estimatedFeeCents >= requiredFeeCents) {
        return estimatedFeeCents;
      }

      estimatedFeeCents = requiredFeeCents;
    }

    return estimatedFeeCents;
  }

  Map<String, dynamic> _buildCheckoutFeePreview(Map<String, dynamic> fee) {
    final showBalanceTotal = fee['total'] as double;
    final showBalanceTotalCents = _dollarsToCents(showBalanceTotal);
    final onlinePaymentFeeCents =
        _selectedPaymentTiming == 'online' &&
            _selectedOnlineProvider == 'stripe' &&
            _stripeReady &&
            _passesOnlinePaymentFeeToExhibitor
        ? _calculateOnlinePaymentFeeCentsFromBase(showBalanceTotalCents)
        : 0;
    final totalDueCents = showBalanceTotalCents + onlinePaymentFeeCents;

    return {
      'show_balance_total_cents': showBalanceTotalCents,
      'online_payment_fee_cents': onlinePaymentFeeCents,
      'total_due_cents': totalDueCents,
      'show_balance_total': _centsToDollars(showBalanceTotalCents),
      'online_payment_fee': _centsToDollars(onlinePaymentFeeCents),
      'total_due': _centsToDollars(totalDueCents),
    };
  }

  String? _buildFurDisplay(Map<String, dynamic> it) {
    if (it['is_fur'] != true) return null;

    final furVariety = (it['fur_variety'] ?? '').toString().trim();
    if (furVariety.isNotEmpty) {
      return 'Fur/Wool add-on: $furVariety';
    }

    return 'Fur/Wool add-on: Yes';
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

    final topLevelStripeAccountId =
        (_stripeStatus?['stripe_account_id'] ??
                _stripeStatus?['provider_account_id'] ??
                '')
            .toString()
            .trim();

    return nestedStripeAccountId.isNotEmpty ||
        topLevelStripeAccountId.isNotEmpty;
  }

  bool get _stripeReady {
    if (!_stripeHasAccount) return false;

    final status = (_stripeStatus?['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final accountStatus =
        (_stripeStatus?['account_status'] ??
                (_stripeStatus?['show_payment_account'] is Map
                    ? (_stripeStatus!['show_payment_account']
                          as Map)['account_status']
                    : null) ??
                '')
            .toString()
            .toLowerCase()
            .trim();

    final isRestricted =
        status == 'restricted' ||
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

  bool _providerReady(String provider) {
    for (final option
        in _paymentConfiguration?.providers ??
            const <ShowPaymentProviderOption>[]) {
      if (option.provider == provider) {
        return option.enabled && option.ready;
      }
    }
    return false;
  }

  Future<void> _selectPaymentTiming(String timing) async {
    if (_payingOnline || _confirming) return;
    setState(() {
      _selectedPaymentTiming = timing;
      _msg = null;
    });
  }

  Future<void> _selectOnlineProvider(String provider) async {
    if (_payingOnline || !_providerReady(provider)) return;
    setState(() {
      _selectedOnlineProvider = provider;
      _msg = null;
    });
  }

  bool get _canPayOnline {
    return !_loading &&
        !_payingOnline &&
        !_confirming &&
        !AppSession.isSupportMode &&
        !_deadlinePassed() &&
        _items.isNotEmpty &&
        _selectedPaymentTiming == 'online' &&
        _selectedOnlineProvider != null &&
        _providerReady(_selectedOnlineProvider!) &&
        (_selectedOnlineProvider != 'stripe' || _stripeReady);
  }

  Map<String, dynamic> _calculateFeesForItems(
    List<Map<String, dynamic>> items,
  ) {
    final currency = (_feeSettings?['currency'] ?? 'USD').toString();
    final regularItems = items
        .where((item) => item['is_fur'] != true)
        .toList(growable: false);

    final discountEnabled =
        _feeSettings?['multi_show_discount_enabled'] == true;
    final discountType = (_feeSettings?['multi_show_discount_type'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final discountValue = _asDouble(_feeSettings?['multi_show_discount_value']);
    final discountBasis =
        (_feeSettings?['multi_show_discount_basis'] ?? 'each_show')
            .toString()
            .toLowerCase()
            .trim();
    final discountScope = (_feeSettings?['multi_show_discount_scope'] ?? 'both')
        .toString()
        .toLowerCase()
        .trim();
    final minimumEntries =
        (_feeSettings?['multi_show_discount_min_entries'] as num?)?.toInt() ??
        0;
    final maximumEntries =
        (_feeSettings?['multi_show_discount_max_entries'] as num?)?.toInt();
    final minimumShows =
        (_feeSettings?['multi_show_discount_required_shows'] as num?)
            ?.toInt() ??
        0;

    double entriesSubtotal = 0.0;
    double furSubtotal = 0.0;
    double showFeeSubtotal = 0.0;
    int furCount = 0;

    final Set<String> chargedShowFeeKeys = {};

    for (final item in regularItems) {
      final sectionId = (item['section_id'] ?? '').toString();
      final sectionFee = _sectionFeeBySectionId[sectionId];

      final feePerEntry = _asDouble(sectionFee?['fee_per_entry']);
      final feePerShow = _asDouble(sectionFee?['fee_per_show']);

      entriesSubtotal += feePerEntry;

      final exhibitorId = (item['exhibitor_id'] ?? '__unassigned__').toString();
      final showFeeKey = '$exhibitorId|$sectionId';
      if (sectionId.isNotEmpty &&
          !chargedShowFeeKeys.contains(showFeeKey) &&
          feePerShow > 0) {
        chargedShowFeeKeys.add(showFeeKey);
        showFeeSubtotal += feePerShow;
      }
    }

    for (final item in items.where((item) => item['is_fur'] == true)) {
      final sectionId = (item['section_id'] ?? '').toString();
      final sectionFee = _sectionFeeBySectionId[sectionId];
      final furFee = _asDouble(sectionFee?['fur_fee']);

      furSubtotal += furFee;
      furCount += 1;
    }

    double discountAmount = 0.0;
    int qualifyingEntryCount = 0;
    int qualifyingShowCount = 0;

    if (discountEnabled &&
        minimumEntries > 0 &&
        minimumShows > 0 &&
        regularItems.isNotEmpty) {
      final itemsByExhibitor = <String, List<Map<String, dynamic>>>{};

      for (final item in regularItems) {
        final sectionId = (item['section_id'] ?? '').toString();
        final section = _sectionById[sectionId];
        final sectionKind = (section?['kind'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        final isEligibleForScope =
            discountScope == 'both' || sectionKind == discountScope;
        if (!isEligibleForScope) continue;

        final exhibitorId = (item['exhibitor_id'] ?? '__unassigned__')
            .toString();
        itemsByExhibitor
            .putIfAbsent(exhibitorId, () => <Map<String, dynamic>>[])
            .add(item);
      }

      for (final exhibitorItems in itemsByExhibitor.values) {
        final itemsBySection = <String, List<Map<String, dynamic>>>{};

        for (final item in exhibitorItems) {
          final sectionId = (item['section_id'] ?? '').toString();
          if (sectionId.isEmpty) continue;
          itemsBySection
              .putIfAbsent(sectionId, () => <Map<String, dynamic>>[])
              .add(item);
        }

        final qualifyingItems = <Map<String, dynamic>>[];

        if (discountBasis == 'cumulative') {
          final enteredSections =
              itemsBySection.entries
                  .where((entry) => entry.value.isNotEmpty)
                  .toList()
                ..sort((a, b) => b.value.length.compareTo(a.value.length));

          if (enteredSections.length >= minimumShows &&
              exhibitorItems.length >= minimumEntries) {
            qualifyingShowCount += enteredSections.length;

            final maxQualifying = maximumEntries == null
                ? exhibitorItems.length
                : maximumEntries.clamp(0, exhibitorItems.length);

            qualifyingItems.addAll(exhibitorItems.take(maxQualifying));
          }
        } else {
          final qualifyingSections =
              itemsBySection.entries
                  .where((entry) => entry.value.length >= minimumEntries)
                  .toList()
                ..sort((a, b) => b.value.length.compareTo(a.value.length));

          if (qualifyingSections.length >= minimumShows) {
            qualifyingShowCount += qualifyingSections.length;

            for (final section in qualifyingSections) {
              final maxForSection = maximumEntries == null
                  ? section.value.length
                  : maximumEntries.clamp(0, section.value.length);
              qualifyingItems.addAll(section.value.take(maxForSection));
            }
          }
        }

        qualifyingEntryCount += qualifyingItems.length;

        for (final item in qualifyingItems) {
          final sectionId = (item['section_id'] ?? '').toString();
          final sectionFee = _sectionFeeBySectionId[sectionId];
          final regularEntryFee = _asDouble(sectionFee?['fee_per_entry']);

          double itemDiscount = 0.0;
          if (discountType == 'fixed_rate') {
            itemDiscount = regularEntryFee - discountValue;
          } else if (discountType == 'percent') {
            final percent = discountValue > 1
                ? discountValue / 100.0
                : discountValue;
            itemDiscount = regularEntryFee * percent;
          } else if (discountType == 'amount') {
            itemDiscount = discountValue;
          }

          itemDiscount = itemDiscount.clamp(0.0, regularEntryFee).toDouble();
          discountAmount += itemDiscount;
        }
      }
    }

    final total =
        (entriesSubtotal + furSubtotal + showFeeSubtotal) - discountAmount;

    return {
      'currency': currency,
      'entry_count': regularItems.length,
      'fur_count': furCount,
      'entries_subtotal': entriesSubtotal,
      'fur_subtotal': furSubtotal,
      'show_fee': showFeeSubtotal,
      'discount_enabled': discountEnabled,
      'discount_type': discountType,
      'discount_value': discountValue,
      'discount_basis': discountBasis,
      'discount_scope': discountScope,
      'discount_min_entries': minimumEntries,
      'discount_max_entries': maximumEntries,
      'discount_minimum_shows': minimumShows,
      'qualifying_entry_count': qualifyingEntryCount,
      'qualifying_show_count': qualifyingShowCount,
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
    final className = (item['class_name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
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
    final stripeStatus = (uri.queryParameters['stripe'] ?? '')
        .trim()
        .toLowerCase();

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
                    MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
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
      setState(
        () => _msg =
            'Your cart is empty. If you are looking for completed entries please return to the upcoming shows tab and select Entries.',
      );
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

    if (_selectedOnlineProvider == null ||
        !_providerReady(_selectedOnlineProvider!)) {
      setState(() {
        _msg = 'The selected online payment processor is not available.';
      });
      return;
    }

    setState(() {
      _payingOnline = true;
      _msg = null;
      _checkoutUrl = null;
    });

    try {
      if (_selectedOnlineProvider == 'square') {
        await _payWithSquare();
        return;
      }
      final checkoutUrl = await StripeConnectService.createCheckoutSession(
        widget.cartId,
      );

      final uri = Uri.parse(checkoutUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );

      if (!launched) {
        if (!mounted) return;
        setState(() {
          _checkoutUrl = checkoutUrl;
          _msg =
              'Stripe Checkout could not open automatically. Tap Open Payment Page below to continue.';
        });
        return;
      }
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString();
      final friendlyMessage =
          errorText.contains('not yet ready to accept charges') ||
              errorText.contains('Stripe account is not yet ready')
          ? 'Online payment is not available yet. The club’s Stripe setup is incomplete.'
          : 'Online payment failed: $e';

      setState(() {
        _checkoutUrl = null;
        _msg = friendlyMessage;
      });
    } finally {
      if (mounted) {
        setState(() => _payingOnline = false);
      }
    }
  }

  Future<void> _payWithSquare() async {
    _squareClientAttemptKey ??= const Uuid().v4();
    final checkout = await SquareCheckoutService.createHostedCheckout(
      cartId: widget.cartId,
      clientAttemptKey: _squareClientAttemptKey!,
    );
    final launched = await launchUrl(
      Uri.parse(checkout.checkoutUrl),
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_self',
    );
    if (!launched && mounted) {
      setState(() {
        _checkoutUrl = checkout.checkoutUrl;
        _msg =
            'Square Checkout could not open automatically. Tap Open Payment Page below to continue.';
      });
    }
  }

  Future<void> _confirmDayOf() async {
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
      parts.add(
        'Volume discount: -${_money(discountAmount, currency: currency)}',
      );
    }

    parts.add('= ${_money(total, currency: currency)}');

    return parts.join(' • ');
  }

  Widget _buildPaymentChoices() {
    final config = _paymentConfiguration;
    if (config == null) return const SizedBox.shrink();
    final readyProviders = config.providers
        .where((provider) => provider.enabled && provider.ready)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  if (config.allowOnline)
                    const ButtonSegment(
                      value: 'online',
                      label: Text('Pay online'),
                      icon: Icon(Icons.credit_card),
                    ),
                  if (config.allowAtShow)
                    const ButtonSegment(
                      value: 'at_show',
                      label: Text('Pay at show'),
                      icon: Icon(Icons.storefront),
                    ),
                ],
                selected: {_selectedPaymentTiming},
                onSelectionChanged: _payingOnline
                    ? null
                    : (values) => _selectPaymentTiming(values.first),
              ),
              if (_selectedPaymentTiming == 'online') ...[
                Text(
                  'Payment processor',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final provider in readyProviders)
                      ChoiceChip(
                        label: Text(
                          provider.provider == 'square'
                              ? 'Square'
                              : provider.provider == 'stripe'
                              ? 'Stripe'
                              : provider.provider,
                        ),
                        selected: _selectedOnlineProvider == provider.provider,
                        onSelected: _payingOnline
                            ? null
                            : (_) => _selectOnlineProvider(provider.provider),
                      ),
                  ],
                ),
                if (readyProviders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No online payment processor is currently ready.',
                    ),
                  ),
                if (_selectedOnlineProvider == 'square') ...[
                  const SizedBox(height: 10),
                Text(
                  'You’ll be redirected to Square to securely enter your payment information.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF162C48),
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overallFee = _calculateFeesForItems(_items);
    final currency = overallFee['currency'] as String;
    final checkoutPreview = _buildCheckoutFeePreview(overallFee);
    final onlinePaymentFee = checkoutPreview['online_payment_fee'] as double;
    final totalDue = checkoutPreview['total_due'] as double;
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
                    MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
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
                        'Support Mode — You are managing this cart while viewing as another user. Online payment remains disabled.',
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
                        color: Colors.red.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: .25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _msg!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_checkoutUrl != null) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                launchUrl(
                                  Uri.parse(_checkoutUrl!),
                                  mode: LaunchMode.platformDefault,
                                  webOnlyWindowName: '_self',
                                );
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Open Payment Page'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                _buildPaymentChoices(),
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
                          color: Colors.black.withValues(alpha: .05),
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
                            color: _deadlinePassed()
                                ? Colors.red
                                : Colors.black87,
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
                                  if ((overallFee['discount_amount']
                                          as double) >
                                      0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Multi-show volume discount '
                                        '(${overallFee['qualifying_entry_count']} qualifying entries): '
                                        '-${_money(overallFee['discount_amount'] as double, currency: currency)}',
                                      ),
                                    ),
                                  if (onlinePaymentFee > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '$_onlinePaymentFeeLabel: ${_money(onlinePaymentFee, currency: currency)}',
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    onlinePaymentFee > 0
                                        ? 'Total Due Today: ${_money(totalDue, currency: currency)}'
                                        : 'Total: ${_money(overallFee['total'] as double, currency: currency)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  if (onlinePaymentFee > 0) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.navy.withValues(
                                          alpha: .05,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.navy.withValues(
                                            alpha: .10,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        _onlinePaymentFeeDescription,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                        const SizedBox(height: 14),
                        Text(
                          _selectedPaymentTiming == 'online' &&
                                  _selectedOnlineProvider != null &&
                                  _providerReady(_selectedOnlineProvider!)
                              ? 'Online payment available'
                              : 'Pay-at-show checkout selected',
                          style: TextStyle(
                            color:
                                _selectedPaymentTiming == 'online' &&
                                    _selectedOnlineProvider != null &&
                                    _providerReady(_selectedOnlineProvider!)
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
                              AppTheme.surfaceTextScope(
                                context,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: .04,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      _ExhibitorGroupHeader(
                                        exhibitorName:
                                            entry.key == '__unassigned__'
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
                                              color: AppColors.text,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            _cartItemSubtitle(it),
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                            ),
                                          ),
                                          isThreeLine: _cartItemIsThreeLine(it),
                                          trailing: IconButton(
                                            tooltip: 'Remove',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed:
                                                (_confirming || _payingOnline)
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
                              ),
                            ],
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: _selectedPaymentTiming == 'online'
                        ? FilledButton.icon(
                            onPressed: _canPayOnline ? _payOnline : null,
                            icon: const Icon(Icons.credit_card),
                            label: Text(
                              _payingOnline
                                  ? 'Processing…'
                                  : _selectedOnlineProvider == 'square'
                                  ? 'Continue to Secure Square Checkout'
                                  : 'Pay ${_money(totalDue, currency: currency)} Online',
                            ),
                          )
                        : FilledButton(
                            onPressed:
                                (_confirming ||
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
        color: AppColors.navy.withValues(alpha: .06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exhibitorName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (feeSettingsExists && feeLine != null) ...[
            const SizedBox(height: 4),
            Text(
              feeLine!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
