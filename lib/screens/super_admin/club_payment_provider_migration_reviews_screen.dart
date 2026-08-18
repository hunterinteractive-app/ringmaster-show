import 'package:flutter/material.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClubPaymentProviderMigrationReviewsScreen extends StatefulWidget {
  const ClubPaymentProviderMigrationReviewsScreen({super.key});

  @override
  State<ClubPaymentProviderMigrationReviewsScreen> createState() =>
      _ClubPaymentProviderMigrationReviewsScreenState();
}

class _ClubPaymentProviderMigrationReviewsScreenState
    extends State<ClubPaymentProviderMigrationReviewsScreen> {
  late Future<List<Map<String, dynamic>>> _reviews = _loadReviews();

  Future<List<Map<String, dynamic>>> _loadReviews() async {
    final rows = await Supabase.instance.client
        .from('club_payment_provider_migration_reviews')
        .select('id, provider, reason, status, created_at, clubs(name), shows(name)')
        .eq('status', 'pending')
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  String _relatedName(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is Map) return value['name']?.toString() ?? 'Unknown';
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map)['name']?.toString() ?? 'Unknown';
    }
    return 'Unknown';
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'conflicting_provider_account':
        return 'Different accounts were linked to shows for this club.';
      case 'missing_provider_account_identifier':
        return 'The legacy connection is missing its provider account ID.';
      default:
        return reason.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Club Payment Provider Reviews',
      subtitle: 'Superadmin',
      showBackButton: true,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reviews,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load migration reviews: ${snapshot.error}'),
              ),
            );
          }
          final reviews = snapshot.data ?? const <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _reviews = _loadReviews());
              await _reviews;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Needs review',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.headerForeground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Only connections that could not be safely assigned to a single hosting-club account are listed here. No money or credentials were moved for these records.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.headerForeground.withValues(alpha: .86),
                  ),
                ),
                const SizedBox(height: 16),
                if (reviews.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No payment-provider migration reviews are pending.'),
                    ),
                  ),
                ...reviews.map((review) {
                  final provider = review['provider']?.toString().toUpperCase() ?? 'PROVIDER';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _relatedName(review, 'clubs'),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text('Show: ${_relatedName(review, 'shows')}'),
                            const SizedBox(height: 10),
                            Chip(label: Text(provider)),
                            const SizedBox(height: 6),
                            Text(_reasonLabel(review['reason']?.toString() ?? 'unknown')),
                            const SizedBox(height: 8),
                            Text(
                              'Pending review',
                              style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
