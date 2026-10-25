import 'dart:async';
import 'package:flutter/material.dart';
import '../models/convention_sale.dart';
import '../screens/convention_sale_screen.dart';
import '../services/convention_sale_service.dart';
import '../theme/app_theme.dart';

class ConventionSaleBanner extends StatefulWidget {
  const ConventionSaleBanner({super.key});
  @override
  State<ConventionSaleBanner> createState() => _ConventionSaleBannerState();
}

class _ConventionSaleBannerState extends State<ConventionSaleBanner>
    with WidgetsBindingObserver {
  ConventionSale? _sale;
  DateTime? _serverTime;
  final _elapsed = Stopwatch();
  Timer? _poll, _boundary;
  bool _loading = false;

  DateTime? get _now => _serverTime?.add(_elapsed.elapsed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted && state == AppLifecycleState.resumed) {
      setState(() {});
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _boundary?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await ConventionSaleService.settings();
      if (!mounted) return;
      _boundary?.cancel();
      setState(() {
        _sale = ConventionSale(data);
        _serverTime = DateTime.tryParse('${data['server_now']}');
        _elapsed
          ..reset()
          ..start();
      });
      final now = _now;
      if (now == null) return;
      final edges =
          [
              DateTime.tryParse('${data['starts_at']}'),
              DateTime.tryParse('${data['ends_at']}'),
            ].whereType<DateTime>().where((edge) => edge.isAfter(now)).toList()
            ..sort();
      if (edges.isNotEmpty) {
        _boundary = Timer(edges.first.difference(now), () {
          if (!mounted) return;
          setState(() {});
          _load();
        });
      }
    } catch (_) {
      if (mounted) {
        _boundary?.cancel();
        setState(() => _sale = null);
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = _sale;
    final now = _now;
    if (sale == null || now == null || !sale.isActiveAt(now)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: const Icon(
            Icons.local_offer_outlined,
            color: AppColors.navy,
          ),
          title: Text(
            sale.title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '${sale.venue} • View token offers',
            style: const TextStyle(color: AppColors.navy),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.navy),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ConventionSaleScreen(),
            ),
          ),
        ),
      ),
    );
  }
}
