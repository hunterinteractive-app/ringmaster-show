import 'package:flutter/material.dart';
import '../screens/convention_sale_screen.dart';
import '../services/convention_sale_service.dart';
import '../theme/app_theme.dart';

class ConventionSaleBanner extends StatefulWidget {
  const ConventionSaleBanner({super.key});
  @override
  State<ConventionSaleBanner> createState() => _ConventionSaleBannerState();
}

class _ConventionSaleBannerState extends State<ConventionSaleBanner> {
  late final Future<Map<String, dynamic>?> _sale = _load();
  Future<Map<String, dynamic>?> _load() async {
    try {
      return await ConventionSaleService.settings();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _sale,
    builder: (context, snapshot) {
      final sale = snapshot.data;
      if (sale == null ||
          sale['enabled'] != true ||
          DateTime.parse(
            sale['server_now'] as String,
          ).isAfter(DateTime.parse(sale['ends_at'] as String))) {
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
              '${sale['title']}',
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              '${sale['venue']} • View token offers',
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
    },
  );
}
