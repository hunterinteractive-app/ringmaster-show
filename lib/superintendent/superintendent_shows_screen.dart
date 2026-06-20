// lib/superintendent/superintendent_shows_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/services/app_session.dart';
import 'package:ringmaster_show/services/role_service.dart';
import 'package:ringmaster_show/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_show/superintendent/superintendent_lineup_screen.dart';
import 'package:ringmaster_show/superintendent/superintendent_preferences_screen.dart';

final supabase = Supabase.instance.client;

class SuperintendentShowsScreen extends StatefulWidget {
  const SuperintendentShowsScreen({super.key});

  @override
  State<SuperintendentShowsScreen> createState() => _SuperintendentShowsScreenState();
}

class _SuperintendentShowsScreenState extends State<SuperintendentShowsScreen> {
  late Future<List<Map<String, dynamic>>> _showsFuture;

  @override
  void initState() {
    super.initState();
    _showsFuture = _loadSuperintendentShows();
  }

  Future<void> _refresh() async {
    setState(() {
      _showsFuture = _loadSuperintendentShows();
    });
    await _showsFuture;
  }

  Future<List<Map<String, dynamic>>> _loadSuperintendentShows() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final isSuperAdmin = !AppSession.isSupportMode && await RoleService.isSuperAdmin();

    if (isSuperAdmin) {
      final rows = await supabase
          .from('shows')
          .select('id, name, start_date, end_date, location_name')
          .order('start_date', ascending: false);

      return List<Map<String, dynamic>>.from(rows as List);
    }

    final roleRows = await supabase
        .from('role_assignments')
        .select('show_id')
        .eq('user_id', userId)
        .eq('role', 'superintendent');

    final showIds = List<Map<String, dynamic>>.from(roleRows as List)
        .map((row) => row['show_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    if (showIds.isEmpty) return [];

    final rows = await supabase
        .from('shows')
        .select('id, name, start_date, end_date, location_name')
        .inFilter('id', showIds)
        .order('start_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows as List);
  }

  String _formatDateRange(Map<String, dynamic> show) {
    final start = (show['start_date'] ?? '').toString();
    final end = (show['end_date'] ?? '').toString();

    if (start.isEmpty && end.isEmpty) return 'Date not set';
    if (end.isEmpty || end == start) return start;
    return '$start – $end';
  }

  String _formatLocation(Map<String, dynamic> show) {
    final location = (show['location_name'] ?? '').toString().trim();
    if (location.isNotEmpty) return location;
    return 'Location not set';
  }

  void _openLineup(Map<String, dynamic> show) {
    final showId = (show['id'] ?? '').toString();
    if (showId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open line-up: missing show ID.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SuperintendentLineupScreen(
          showId: showId,
          showName: (show['name'] ?? 'Show').toString(),
        ),
      ),
    );
  }

  void _openPreferences() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SuperintendentPreferencesScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Show Superintendent',
      subtitle: 'Build and manage judging line-ups for your assigned shows.',
      actions: [
        TextButton.icon(
          onPressed: AppSession.isSupportMode ? null : _openPreferences,
          icon: const Icon(Icons.tune),
          label: const Text('Preferences'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white54,
          ),
        ),
        IconButton(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _showsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: _refresh,
            );
          }

          final shows = snapshot.data ?? const <Map<String, dynamic>>[];

          final supportBanner = AppSession.isSupportMode
              ? Padding(
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
                      'Support Mode — Showing superintendent access for the user you are viewing. Preferences are disabled.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              : null;

          if (shows.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  if (supportBanner != null) supportBanner,
                  const SizedBox(height: 120),
                  const _EmptyState(),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: shows.length + (supportBanner == null ? 0 : 1),
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (supportBanner != null && index == 0) {
                  return supportBanner;
                }

                final showIndex = index - (supportBanner == null ? 0 : 1);
                final show = shows[showIndex];
                return _ShowCard(
                  showName: (show['name'] ?? 'Untitled Show').toString(),
                  dateRange: _formatDateRange(show),
                  location: _formatLocation(show),
                  onTap: () => _openLineup(show),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ShowCard extends StatelessWidget {
  const _ShowCard({
    required this.showName,
    required this.dateRange,
    required this.location,
    required this.onTap,
  });

  final String showName;
  final String dateRange;
  final String location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.fact_check,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      dateRange,
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No superintendent shows found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Shows will appear here when you are assigned the superintendent role.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 56,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to load superintendent shows',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}