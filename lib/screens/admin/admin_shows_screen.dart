// lib/screens/admin/admin_shows_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../create_show_screen.dart';
import 'edit_show_settings_screen.dart';
import '../../screens/show_list_screen.dart';
import '../../screens/my_animals_screen.dart';
import '../../screens/my_entries_screen.dart';
import '../../screens/account_settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

final supabase = Supabase.instance.client;

class AdminShowsScreen extends StatefulWidget {
  final List<String> allowedShowIds;

  const AdminShowsScreen({
    super.key,
    required this.allowedShowIds,
  });

  @override
  State<AdminShowsScreen> createState() => _AdminShowsScreenState();
}

class _AdminShowsScreenState extends State<AdminShowsScreen> {
  late Future<_AdminShowsPageData> _pageFuture;

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
    if (v == null || v.isEmpty) return '—';
    return v.length >= 10 ? v.substring(0, 10) : v;
  }

  String _fmtTs(String? v) {
    if (v == null || v.trim().isEmpty) return '—';
    final dt = DateTime.tryParse(v);
    if (dt == null) return '—';
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
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
      MaterialPageRoute(
        builder: (_) => EditShowSettingsScreen(showId: showId),
      ),
    );
    if (mounted) {
      await _reload();
    }
  }

  void _openShows() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ShowListScreen()),
    );
  }

  void _openAnimals() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
    );
  }

  void _openEntries() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
    );
  }

  void _openAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
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

    return RMCard(
      child: Row(
        children: [
          Icon(
            license.canCreate
                ? Icons.check_circle_outline
                : Icons.warning_amber_rounded,
            color: license.canCreate ? AppColors.success : Colors.orange,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: license.canCreate ? AppColors.success : Colors.orange,
                fontWeight: FontWeight.w700,
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
          appBar: _AdminShowsAppBar(
            canCreate: license.canCreate &&
                snap.connectionState != ConnectionState.waiting,
            onShows: _openShows,
            onAnimals: _openAnimals,
            onEntries: _openEntries,
            onAccount: _openAccount,
            onReload: snap.connectionState == ConnectionState.waiting
                ? null
                : _reload,
            onCreate: (snap.connectionState == ConnectionState.waiting ||
                    !license.canCreate)
                ? null
                : _openCreate,
          ),
          body: snap.connectionState != ConnectionState.done
              ? const Center(child: CircularProgressIndicator())
              : snap.hasError
                  ? Center(child: Text('Error: ${snap.error}'))
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          _buildLicenseBanner(license),
                          const SizedBox(height: AppSpacing.md),
                          if (widget.allowedShowIds.isEmpty)
                            const Expanded(
                              child: RMEmptyState(
                                title: 'No admin access yet',
                                subtitle:
                                    'You do not currently have admin access to any shows.',
                                icon: Icons.admin_panel_settings_outlined,
                              ),
                            )
                          else if ((page?.shows ?? []).isEmpty)
                            const Expanded(
                              child: RMEmptyState(
                                title: 'No shows available',
                                subtitle:
                                    'No shows were found for your current admin access.',
                                icon: Icons.event_busy_outlined,
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                itemCount: page!.shows.length,
                                itemBuilder: (context, i) {
                                  final s = page.shows[i];

                                  final showId = s['id'].toString();
                                  final name = (s['name'] ?? '').toString();
                                  final start =
                                      _fmtDate((s['start_date'] ?? '').toString());
                                  final end =
                                      _fmtDate((s['end_date'] ?? '').toString());
                                  final loc =
                                      (s['location_name'] ?? '').toString();
                                  final published = s['is_published'] == true;

                                  final openAt =
                                      _fmtTs(s['entry_open_at']?.toString());
                                  final closeAt =
                                      _fmtTs(s['entry_close_at']?.toString());

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpacing.md,
                                    ),
                                    child: RMCard(
                                      onTap: () => _openEditShow(showId),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                              ),
                                              RMBadge(
                                                text: published
                                                    ? 'Published'
                                                    : 'Draft',
                                                icon: published
                                                    ? Icons.public
                                                    : Icons.edit_note,
                                                success: published,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.sm,
                                          ),
                                          Text(
                                            '$start${end != '—' ? ' → $end' : ''} • $loc',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppColors.muted,
                                                ),
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.md,
                                          ),
                                          Wrap(
                                            spacing: AppSpacing.sm,
                                            runSpacing: AppSpacing.sm,
                                            children: [
                                              RMBadge(
                                                text: 'Open: $openAt',
                                                icon: Icons.lock_open,
                                              ),
                                              RMBadge(
                                                text: 'Deadline: $closeAt',
                                                icon: Icons.event_available,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
        );
      },
    );
  }
}

class _AdminShowsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onShows;
  final VoidCallback onAnimals;
  final VoidCallback onEntries;
  final VoidCallback onAccount;
  final VoidCallback? onReload;
  final VoidCallback? onCreate;
  final bool canCreate;

  const _AdminShowsAppBar({
    required this.onShows,
    required this.onAnimals,
    required this.onEntries,
    required this.onAccount,
    required this.onReload,
    required this.onCreate,
    required this.canCreate,
  });

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showLabels = width >= 1100;

    return AppBar(
      toolbarHeight: 92,
      titleSpacing: 16,
      title: Row(
        children: [
          Image.asset(
            'assets/images/ringmaster_show_logo.png',
            height: 48,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RingMaster Show',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                'Admin Shows',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withOpacity(.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        _TopBarAction(
          icon: Icons.event,
          label: 'Shows',
          showLabel: showLabels,
          onTap: onShows,
        ),
        _TopBarAction(
          icon: Icons.pets,
          label: 'Animals',
          showLabel: showLabels,
          onTap: onAnimals,
        ),
        _TopBarAction(
          icon: Icons.receipt_long,
          label: 'Entries',
          showLabel: showLabels,
          onTap: onEntries,
        ),
        _TopBarAction(
          icon: Icons.manage_accounts,
          label: 'Account',
          showLabel: showLabels,
          onTap: onAccount,
        ),
        _TopBarAction(
          icon: Icons.refresh,
          label: 'Reload',
          showLabel: showLabels,
          onTap: onReload,
        ),
        _TopBarAction(
          icon: Icons.add,
          label: 'Create Show',
          showLabel: showLabels,
          onTap: onCreate,
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback? onTap;

  const _TopBarAction({
    required this.icon,
    required this.label,
    required this.showLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!showLabel) {
      return IconButton(
        tooltip: label,
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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