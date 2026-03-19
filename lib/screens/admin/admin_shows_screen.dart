// lib/screens/admin/admin_shows_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../create_show_screen.dart';
import 'edit_show_settings_screen.dart';

final supabase = Supabase.instance.client;

class AdminShowsScreen extends StatefulWidget {
  /// Only these shows will appear in Admin.
  /// Pass from ShowListScreen based on show_admins rows.
  final List<String> allowedShowIds;

  const AdminShowsScreen({
    super.key,
    required this.allowedShowIds,
  });

  @override
  State<AdminShowsScreen> createState() => _AdminShowsScreenState();
}

class _AdminShowsScreenState extends State<AdminShowsScreen> {
  late final Future<_AdminShowsPageData> _pageFuture;

  @override
  void initState() {
    super.initState();
    _pageFuture = _loadPage();
  }

  Future<_AdminShowsPageData> _loadPage() async {
    final shows = await _loadShows();
    final license = await _loadLicenseStatus();
    return _AdminShowsPageData(
      shows: shows,
      license: license,
    );
  }

  Future<List<Map<String, dynamic>>> _loadShows() async {
    if (widget.allowedShowIds.isEmpty) return [];

    final res = await supabase
        .from('shows')
        .select(
          'id,name,start_date,end_date,location_name,is_published,entry_open_at,entry_close_at,created_at',
        )
        .inFilter('id', widget.allowedShowIds)
        .order('start_date');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<_ShowCreationStatus> _loadLicenseStatus() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const _ShowCreationStatus(
        canCreate: false,
        remainingShowDays: 0,
        unlimitedActive: false,
        unlimitedExpiresAt: null,
        message: 'Not signed in.',
      );
    }

    try {
      final result = await supabase.rpc(
        'show_creation_status',
        params: {'p_user_id': user.id},
      );

      if (result is List && result.isNotEmpty) {
        final row = Map<String, dynamic>.from(result.first as Map);
        return _ShowCreationStatus.fromMap(row);
      }

      if (result is Map) {
        return _ShowCreationStatus.fromMap(
          Map<String, dynamic>.from(result),
        );
      }

      return const _ShowCreationStatus(
        canCreate: false,
        remainingShowDays: 0,
        unlimitedActive: false,
        unlimitedExpiresAt: null,
        message: 'No license found.',
      );
    } catch (e) {
      return _ShowCreationStatus(
        canCreate: false,
        remainingShowDays: 0,
        unlimitedActive: false,
        unlimitedExpiresAt: null,
        message: 'License check failed: $e',
      );
    }
  }

  String _fmtDate(String? v) {
    if (v == null || v.isEmpty) return '';
    return v.length >= 10 ? v.substring(0, 10) : v;
  }

  String _fmtTs(String? v) {
    if (v == null || v.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(v);
    if (dt == null) return '—';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _reload() async {
    setState(() {
      _pageFuture = _loadPage();
    });
  }

  Future<void> _openCreate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateShowScreen()),
    );
    if (ok == true && mounted) {
      await _reload();
    }
  }

  Future<void> _openEditShow(String showId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditShowSettingsScreen(showId: showId)),
    );
    if (mounted) {
      await _reload();
    }
  }

  Widget _buildLicenseBanner(_ShowCreationStatus license) {
    String text;

    if (license.unlimitedActive) {
      final expires = license.unlimitedExpiresAt == null
          ? ''
          : ' • Expires ${_fmtTs(license.unlimitedExpiresAt)}';
      text = 'Unlimited plan active$expires';
    } else {
      final days = license.remainingShowDays;
      text = '$days show day${days == 1 ? '' : 's'} remaining';
    }

    final color = license.canCreate ? Colors.green : Colors.orange;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            license.canCreate ? Icons.check_circle_outline : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminShowsPageData>(
      future: _pageFuture,
      builder: (context, snap) {
        final page = snap.data;
        final license = page?.license ??
            const _ShowCreationStatus(
              canCreate: false,
              remainingShowDays: 0,
              unlimitedActive: false,
              unlimitedExpiresAt: null,
              message: 'Loading license…',
            );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin: Shows'),
            actions: [
              IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh),
                onPressed: snap.connectionState == ConnectionState.waiting ? null : _reload,
              ),
              IconButton(
                tooltip: license.canCreate ? 'Create Show' : (license.message ?? 'Cannot create show'),
                icon: const Icon(Icons.add),
                onPressed: (snap.connectionState == ConnectionState.waiting || !license.canCreate)
                    ? null
                    : _openCreate,
              ),
            ],
          ),
          body: snap.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : snap.hasError
                  ? Center(child: Text('Error: ${snap.error}'))
                  : Column(
                      children: [
                        _buildLicenseBanner(license),
                        if (widget.allowedShowIds.isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text('You do not have admin access to any shows.'),
                            ),
                          )
                        else if ((page?.shows ?? []).isEmpty)
                          const Expanded(
                            child: Center(
                              child: Text('No shows available for your admin access.'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              itemCount: page!.shows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final s = page.shows[i];

                                final showId = s['id'].toString();
                                final name = (s['name'] ?? '').toString();
                                final start = _fmtDate((s['start_date'] ?? '').toString());
                                final end = _fmtDate((s['end_date'] ?? '').toString());
                                final loc = (s['location_name'] ?? '').toString();
                                final published = s['is_published'] == true;

                                final openAt = _fmtTs(s['entry_open_at']?.toString());
                                final closeAt = _fmtTs(s['entry_close_at']?.toString());

                                final subtitleLines = <String>[
                                  '$start${end.isNotEmpty ? ' → $end' : ''} • $loc',
                                  'Entries: $openAt → $closeAt',
                                ];

                                return ListTile(
                                  title: Row(
                                    children: [
                                      Expanded(child: Text(name)),
                                      const SizedBox(width: 8),
                                      Chip(label: Text(published ? 'Published' : 'Draft')),
                                    ],
                                  ),
                                  subtitle: Text(subtitleLines.join('\n')),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openEditShow(showId),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
        );
      },
    );
  }
}

class _AdminShowsPageData {
  final List<Map<String, dynamic>> shows;
  final _ShowCreationStatus license;

  const _AdminShowsPageData({
    required this.shows,
    required this.license,
  });
}

class _ShowCreationStatus {
  final bool canCreate;
  final int remainingShowDays;
  final bool unlimitedActive;
  final String? unlimitedExpiresAt;
  final String? message;

  const _ShowCreationStatus({
    required this.canCreate,
    required this.remainingShowDays,
    required this.unlimitedActive,
    required this.unlimitedExpiresAt,
    required this.message,
  });

  factory _ShowCreationStatus.fromMap(Map<String, dynamic> row) {
    return _ShowCreationStatus(
      canCreate: row['can_create'] == true,
      remainingShowDays: (row['remaining_show_days'] as num?)?.toInt() ?? 0,
      unlimitedActive: row['unlimited_active'] == true,
      unlimitedExpiresAt: row['unlimited_expires_at']?.toString(),
      message: row['message']?.toString(),
    );
  }
}