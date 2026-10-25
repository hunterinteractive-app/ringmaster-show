import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../models/convention_sale.dart';
import '../services/app_session.dart';
import '../services/convention_location.dart';
import '../services/convention_sale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/rm_widgets.dart';
import 'login_screen.dart';
import 'legal/privacy_policy_screen.dart';

class ConventionSaleScreen extends StatefulWidget {
  const ConventionSaleScreen({
    super.key,
    this.initialUri,
    this.previewSettings,
  });
  final Uri? initialUri;
  final Map<String, dynamic>? previewSettings;
  @override
  State<ConventionSaleScreen> createState() => _ConventionSaleScreenState();
}

class _ConventionSaleScreenState extends State<ConventionSaleScreen> {
  ConventionSale? _sale;
  List<Map<String, dynamic>> _products = [];
  String? _error, _message, _busyPlan, _requestId, _requestPlan;
  Uri? _checkoutUrl;
  bool _loading = true;
  bool _fulfilled = false;
  bool _checkingReceipt = false;
  Timer? _refreshTimer;
  Timer? _receiptTimer;
  int _receiptAttempts = 0;
  bool get _preview => widget.previewSettings != null;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
    if (!_preview) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_busyPlan == null) _refreshSettings();
      });
      final claim = widget.initialUri?.queryParameters['purchase'];
      if (claim != null) {
        _message = 'Confirming your payment and convention bonus…';
        _checkReceipt(claim);
        _receiptTimer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => _checkReceipt(claim),
        );
      } else if (widget.initialUri?.queryParameters['cancelled'] == '1') {
        _message =
            'Checkout was canceled. You can choose a package and try again.';
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _receiptTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data =
          widget.previewSettings ?? await ConventionSaleService.settings();
      if (!mounted) return;
      setState(() {
        _sale = ConventionSale(data);
        _loading = false;
        _error = null;
      });
      final catalog = await ConventionSaleService.catalog();
      if (mounted) {
        setState(
          () => _products = (catalog['products'] as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _sale == null
              ? 'The convention sale is unavailable. Please retry or visit the booth for help.'
              : 'Token pricing could not load. Please retry or visit the booth for help.';
        });
      }
    }
  }

  Future<void> _refreshSettings() async {
    try {
      final data = await ConventionSaleService.settings();
      if (mounted) setState(() => _sale = ConventionSale(data));
    } catch (_) {
      /* Checkout still checks the server's sale window. */
    }
  }

  Future<void> _checkReceipt(String claim) async {
    if (_checkingReceipt) return;
    if (_receiptAttempts++ >= 20) {
      _receiptTimer?.cancel();
      return;
    }
    if (_db.auth.currentUser == null) {
      if (mounted) {
        setState(
          () => _message =
              'Sign in to the account used for checkout to view your purchase confirmation.',
        );
      }
      return;
    }
    _checkingReceipt = true;
    try {
      final result = await ConventionSaleService.purchase(claim);
      if (!mounted) return;
      if (result?['fulfilled'] == true) {
        _receiptTimer?.cancel();
        final summary = conventionPurchaseConfirmation(result!);
        setState(() {
          _fulfilled = true;
          _requestId = null;
          _requestPlan = null;
          _checkoutUrl = null;
          _message = summary;
        });
      } else if (result == null) {
        _receiptTimer?.cancel();
        setState(
          () => _message =
              'This purchase could not be found for your account. Use the same RingMaster account you signed into for checkout.',
        );
      } else {
        setState(
          () => _message =
              'Your purchase is awaiting payment confirmation. Tokens and bonus access are added automatically after payment succeeds.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Payment confirmation is still pending. Refresh this page later to check your purchase.',
        );
      }
    } finally {
      _checkingReceipt = false;
    }
  }

  Future<void> _buy(String plan) async {
    if (_preview || _busyPlan != null) return;
    if (_db.auth.currentUser == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            afterLogin: (_) =>
                ConventionSaleScreen(initialUri: widget.initialUri),
          ),
        ),
      );
      return;
    }
    if (AppSession.isSupportMode) {
      setState(() => _error = 'Exit View As User before making a purchase.');
      return;
    }
    setState(() {
      _busyPlan = plan;
      _error = null;
      _message = 'Checking your location for the convention bonus…';
      _checkoutUrl = null;
    });
    try {
      final location = await checkConventionLocation();
      if (!mounted) return;
      if (_requestPlan != plan) {
        _requestPlan = plan;
        _requestId = null;
      }
      _requestId ??= const Uuid().v4();
      final result = await ConventionSaleService.checkout(
        plan,
        _requestId!,
        location,
      );
      if (!mounted) return;
      final url = Uri.parse(result['url'] as String);
      if (url.scheme != 'https' || url.host != 'checkout.stripe.com') {
        throw StateError('Checkout returned an invalid payment address.');
      }
      setState(() {
        _checkoutUrl = url;
        _message = 'Location confirmed. Opening your secure checkout…';
      });
      await launchUrl(url, webOnlyWindowName: '_self');
    } catch (e) {
      if (!mounted) return;
      final text = e is StateError
          ? e.message.toString()
          : 'Unable to open checkout. Please retry or visit the booth for help.';
      // A declined location check is a completed visitor record. A new reading
      // after moving into the area must use a new id, while provider/network
      // retries retain their id to avoid creating another payment session.
      if (text.contains('expired') ||
          text.contains('does not match') ||
          text.contains('inside the sale area') ||
          text.contains('fresh, accurate')) {
        _requestId = null;
        _requestPlan = null;
      }
      setState(() {
        _error = text;
        _message = null;
      });
    } finally {
      if (mounted) setState(() => _busyPlan = null);
    }
  }

  Future<void> _receiptAction() async {
    if (_db.auth.currentUser == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            afterLogin: (_) =>
                ConventionSaleScreen(initialUri: widget.initialUri),
          ),
        ),
      );
    } else {
      _receiptAttempts = 0;
      final claim = widget.initialUri?.queryParameters['purchase'];
      if (claim != null) await _checkReceipt(claim);
    }
  }

  String _price(String plan) {
    final product = _products.where((p) => p['plan'] == plan).firstOrNull;
    if (product == null) {
      return _preview ? 'Regular package price' : 'Loading price…';
    }
    final format = NumberFormat.simpleCurrency(
      name: (product['currency'] as String).toUpperCase(),
    );
    return format.format(
      (product['amount'] as num) / math.pow(10, format.decimalDigits ?? 2),
    );
  }

  Widget _offer(String plan, double width) {
    final sale = _sale!;
    final unlimited = plan == 'unlimited';
    final base = switch (plan) {
      'single_show' => 'Buy 1 token',
      'four_shows' => 'Buy 4 tokens',
      _ => 'Buy unlimited',
    };
    final bonus = sale.bonusFor(plan);
    return SizedBox(
      width: width,
      child: RMCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              unlimited
                  ? Icons.all_inclusive
                  : Icons.confirmation_number_outlined,
              color: AppColors.secondaryButton,
              size: 32,
            ),
            const SizedBox(height: 18),
            Text(
              base,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _price(plan),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+$bonus bonus ${unlimited
                    ? 'months'
                    : bonus == 1
                    ? 'token'
                    : 'tokens'}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              sale.totalFor(plan),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              unlimited
                  ? 'Extends existing access from its expiration date, or starts when your purchase is confirmed.'
                  : 'One token covers one show day. Your bonus tokens are added to the same account.',
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    !_preview &&
                        sale.active &&
                        _products.isNotEmpty &&
                        _busyPlan == null
                    ? () => _buy(plan)
                    : null,
                icon: _busyPlan == plan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.location_on_outlined),
                label: Text(
                  _preview
                      ? 'Preview only'
                      : _db.auth.currentUser == null
                      ? 'Sign in to purchase'
                      : 'Check location & buy',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sale = _sale;
    return Scaffold(
      backgroundColor: AppColors.pageBackgroundDeep,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(gradient: AppGradients.page),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/RingMaster_One_Show_Transparent.png',
                                height: 64,
                                width: 90,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'RingMaster Show',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              if (_preview)
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text(
                                    'Close preview',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Text(
                              _preview
                                  ? 'SALE PREVIEW • CHECKOUT DISABLED'
                                  : 'CONVENTION EXCLUSIVE',
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            sale?.title ?? 'Convention token bonus',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (sale != null) ...[
                            Text(
                              'A little extra for being here.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${sale.venue}\n${sale.data['address']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              sale.hours,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Available within ${sale.radiusMiles.toStringAsFixed(1)} miles of the convention. Bonus included on every qualifying purchase.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                height: 1.5,
                              ),
                            ),
                            if (!sale.active && !_preview)
                              Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: Text(
                                  !sale.enabled
                                      ? 'The convention sale is paused.'
                                      : DateTime.parse(
                                          sale.data['server_now'] as String,
                                        ).isBefore(
                                          DateTime.parse(
                                            sale.data['starts_at'] as String,
                                          ),
                                        )
                                      ? 'The sale opens at the time listed above.'
                                      : 'This convention sale has ended.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.gold,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                          if (_message != null || _error != null) ...[
                            const SizedBox(height: 22),
                            Semantics(
                              liveRegion: true,
                              child: RMCard(
                                child: Column(
                                  children: [
                                    Text(
                                      _error ?? _message!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _error != null
                                            ? AppColors.danger
                                            : _fulfilled
                                            ? AppColors.success
                                            : AppColors.navy,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (_error != null)
                                      TextButton(
                                        onPressed: _load,
                                        child: const Text('Reload sale'),
                                      ),
                                    if (_checkoutUrl != null)
                                      TextButton(
                                        onPressed: () => launchUrl(
                                          _checkoutUrl!,
                                          webOnlyWindowName: '_self',
                                        ),
                                        child: const Text(
                                          'Open secure checkout',
                                        ),
                                      ),
                                    if (_fulfilled)
                                      TextButton(
                                        onPressed: () {
                                          _requestId = null;
                                          _requestPlan = null;
                                          setState(() {
                                            _fulfilled = false;
                                            _message = null;
                                          });
                                        },
                                        child: const Text(
                                          'Make another qualifying purchase',
                                        ),
                                      ),
                                    if (!_fulfilled &&
                                        widget
                                                .initialUri
                                                ?.queryParameters['purchase'] !=
                                            null)
                                      TextButton(
                                        onPressed: _receiptAction,
                                        child: Text(
                                          _db.auth.currentUser == null
                                              ? 'Sign in to view purchase'
                                              : 'Check purchase status',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (sale != null) ...[
                            const SizedBox(height: 30),
                            const Text(
                              'Buying for yourself or a club? Enter the Show Secretary Name and Email in Stripe. '
                              'The purchase and bonus go to that secretary’s account. '
                              'If they have not registered yet, the purchase is held for their verified email.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 20),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth >= 900
                                    ? (constraints.maxWidth - 32) / 3
                                    : constraints.maxWidth;
                                return Wrap(
                                  spacing: 16,
                                  runSpacing: 16,
                                  children: [
                                    for (final plan in [
                                      'single_show',
                                      'four_shows',
                                      'unlimited',
                                    ])
                                      _offer(plan, width),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.gold,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Your location, just for this purchase.',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'When you check out, we ask permission to check your location once. We use the U.S. Census geocoder to identify your city and state, then save those names, the check time and eligibility result with your account for review by authorized RingMaster staff. This is your location during the check, not your home address. Precise visitor coordinates are not stored in the sale records.\nStart checkout during sale hours and complete it within one hour. Tax is shown at checkout.\nLocation unavailable or permission declined? Visit the booth for help.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.6,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => const PrivacyPolicyScreen(),
                                  ),
                                ),
                                child: const Text(
                                  'Privacy policy',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                              if (!_preview)
                                TextButton(
                                  onPressed: () => launchUrl(
                                    Uri.parse('${Uri.base.origin}/'),
                                    webOnlyWindowName: '_self',
                                  ),
                                  child: const Text(
                                    'Continue to RingMaster',
                                    style: TextStyle(color: Colors.white),
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
      ),
    );
  }
}
