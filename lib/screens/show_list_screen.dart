// lib/screens/show_list_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/screens/admin/admin_shows_screen.dart';
import 'package:ringmaster_show/screens/admin/edit_show_settings_screen.dart';
import 'package:ringmaster_show/screens/super_admin/superadmin_home_screen.dart';

import 'login_screen.dart';
import 'my_animals_screen.dart';
import 'enter_show_screen.dart';
import 'account_settings_screen.dart';
import 'my_entries_screen.dart';

import '../services/role_service.dart';
import '../utils/date_time_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/rm_widgets.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../widgets/rm_timezone_notice_banner.dart';

final supabase = Supabase.instance.client;

class ShowListScreen extends StatelessWidget {
  const ShowListScreen({super.key});

  Future<List<Map<String, dynamic>>> _loadShows() async {
    final now = DateTime.now().toUtc().toIso8601String();

    final res = await supabase
        .from('shows')
        .select('id,name,start_date,location_name,entry_close_at')
        .eq('is_published', true)
        .or('entry_close_at.is.null,entry_close_at.gte.$now')
        .order('start_date');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Set<String>> _loadAdminShowIds() async {
    final user = supabase.auth.currentUser;
    if (user == null) return <String>{};

    final rows = await supabase
        .from('role_assignments')
        .select('show_id, role')
        .eq('user_id', user.id);

    const allowedRoles = {
      'super_admin',
      'admin',
      'superintendent',
      'reporting_clerk',
    };

    return (rows as List)
        .cast<Map<String, dynamic>>()
        .where((r) => allowedRoles.contains((r['role'] ?? '').toString()))
        .map((r) => (r['show_id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<bool> _hasAnyAssignedShows() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final rows = await supabase
        .from('role_assignments')
        .select('show_id')
        .eq('user_id', user.id)
        .limit(1);

    return (rows as List).isNotEmpty;
  }

  Future<bool> _hasAvailableShowCapacity() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    final row = await supabase
        .from('account_license_balances')
        .select(
          'purchased_show_days, consumed_show_days, unlimited_access, unlimited_active',
        )
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return false;

    final unlimitedAccess = row['unlimited_access'] == true;
    final unlimitedActive = row['unlimited_active'] == true;

    if (unlimitedAccess || unlimitedActive) return true;

    final purchased = (row['purchased_show_days'] as num?)?.toInt() ?? 0;
    final consumed = (row['consumed_show_days'] as num?)?.toInt() ?? 0;

    return purchased > consumed;
  }

  Future<_ShowListBundle> _loadBundle() async {
    final shows = await _loadShows();
    final isSuper = await RoleService.isSuperAdmin();

    List<Map<String, dynamic>> superAdminShows = <Map<String, dynamic>>[];
    if (isSuper) {
      try {
        superAdminShows = await _loadAllShowsForSuperAdmin();
      } catch (_) {
        superAdminShows = <Map<String, dynamic>>[];
      }
    }

    Set<String> adminShowIds = <String>{};
    try {
      adminShowIds = await _loadAdminShowIds();
    } catch (_) {
      adminShowIds = <String>{};
    }

    bool hasAvailableShowCapacity = false;
    try {
      hasAvailableShowCapacity = await _hasAvailableShowCapacity();
    } catch (_) {
      hasAvailableShowCapacity = false;
    }

    bool hasAnyAssignedShows = false;
    try {
      hasAnyAssignedShows = await _hasAnyAssignedShows();
    } catch (_) {
      hasAnyAssignedShows = false;
    }

    return _ShowListBundle(
      shows: shows,
      superAdminShows: superAdminShows,
      adminShowIds: adminShowIds,
      isSuperAdmin: isSuper,
      hasAvailableShowCapacity: hasAvailableShowCapacity,
      hasAnyAssignedShows: hasAnyAssignedShows,
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllShowsForSuperAdmin() async {
    final res = await supabase
        .from('shows')
        .select('id,name,start_date,location_name,entry_close_at,is_published')
        .order('start_date');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _logout(BuildContext context) async {
    await supabase.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _openAdmin(BuildContext context, _ShowListBundle bundle) {
    final allowedShowIds = bundle.isSuperAdmin
        ? bundle.superAdminShowIds.toList()
        : bundle.adminShowIds.toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShowsScreen(
          allowedShowIds: allowedShowIds,
        ),
      ),
    );
  }

  void _openEditShow(BuildContext context, String showId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditShowSettingsScreen(showId: showId),
      ),
    );
  }

  void _openEnterShow(BuildContext context, String showId, String showName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnterShowScreen(
          showId: showId,
          showName: showName,
        ),
      ),
    );
  }

    @override
    Widget build(BuildContext context) {
      return FutureBuilder<_ShowListBundle>(
        future: _loadBundle(),
        builder: (context, snap) {
          final bundle = snap.data;

          return Scaffold(
            appBar: _ResponsiveShowAppBar(
              bundle: bundle,
              showAdmin: bundle?.canSeeAdminButton == true,
              onAdmin: bundle == null ? null : () => _openAdmin(context, bundle),
              onAnimals: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyAnimalsScreen()),
                );
              },
              onEntries: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyEntriesScreen()),
                );
              },
              onSuperAdmin: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SuperadminHomeScreen()),
                );
              },
              onAccount: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
                );
              },
              onLogout: () => _logout(context),
            ),
            body: Builder(
              builder: (_) {
                Widget content;

                if (snap.connectionState != ConnectionState.done) {
                  content = const Center(child: CircularProgressIndicator());
                } else if (snap.hasError) {
                  content = Center(child: Text('Error: ${snap.error}'));
                } else {
                  final bundle = snap.data!;
                  final shows = bundle.shows;

                  if (shows.isEmpty) {
                    content = _UpcomingShowsEmptyState(
                      showAdminButton: bundle.canSeeAdminButton,
                      onAdmin: () => _openAdmin(context, bundle),
                    );
                  } else {
                    content = ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      itemCount: shows.length,
                      itemBuilder: (context, i) {
                        final s = shows[i];
                        final showId = s['id'].toString();
                        final showName = (s['name'] ?? '').toString();
                        final startDate = (s['start_date'] ?? '').toString();
                        final location = (s['location_name'] ?? '').toString();

                        final entryDeadlineText =
                            formatLocalDateTime(s['entry_close_at']?.toString());

                        final deadlinePassed = s['entry_close_at'] != null &&
                            DateTime.parse(
                              s['entry_close_at'].toString(),
                            ).toLocal().isBefore(DateTime.now());

                        final isAdminForShow =
                            bundle.isSuperAdmin || bundle.adminShowIds.contains(showId);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: RMCard(
                            onTap: () => _openEnterShow(context, showId, showName),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        showName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Actions',
                                      onSelected: (v) {
                                        if (v == 'enter') {
                                          _openEnterShow(context, showId, showName);
                                        } else if (v == 'admin') {
                                          _openEditShow(context, showId);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'enter',
                                          child: Text('Enter Show'),
                                        ),
                                        if (isAdminForShow)
                                          const PopupMenuItem(
                                            value: 'admin',
                                            child: Text('Admin Settings'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  '$startDate • $location',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.muted,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.sm,
                                  children: [
                                    RMBadge(
                                      text: deadlinePassed
                                          ? 'Entry Closed'
                                          : 'Entry Deadline: $entryDeadlineText',
                                      icon: Icons.event_available,
                                      danger: deadlinePassed,
                                      success: !deadlinePassed,
                                    ),
                                    if (isAdminForShow)
                                      const RMBadge(
                                        text: 'Admin Access',
                                        icon: Icons.admin_panel_settings,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }
                }

                return Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        12,
                      ),
                      child: RMTimezoneNoticeBanner(),
                    ),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          );
        },
      );
    }
}

class _ResponsiveShowAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final _ShowListBundle? bundle;
  final bool showAdmin;
  final VoidCallback? onAdmin;
  final VoidCallback onAnimals;
  final VoidCallback onEntries;
  final VoidCallback onSuperAdmin;
  final VoidCallback onAccount;
  final VoidCallback onLogout;

  const _ResponsiveShowAppBar({
    required this.bundle,
    required this.showAdmin,
    required this.onAdmin,
    required this.onAnimals,
    required this.onEntries,
    required this.onSuperAdmin,
    required this.onAccount,
    required this.onLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showLabels = width >= 1180;
    final medium = width >= 900;
    final showSuperAdminInline = width >= 1280;

    return AppBar(
      toolbarHeight: 92,
      titleSpacing: 16,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 320;
          final logoSize = compact ? 36.0 : 48.0;
          final titleFont = compact ? 20.0 : 28.0;
          final subtitleFont = compact ? 12.0 : 15.0;

          return Row(
            children: [
              Image.asset(
                'assets/images/ringmaster_show_logo.png',
                height: logoSize,
                width: logoSize,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RingMaster Show',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontSize: titleFont,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Upcoming Shows',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(.9),
                            fontSize: subtitleFont,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        if (showAdmin && onAdmin != null)
          _TopBarAction(
            icon: Icons.admin_panel_settings,
            label: 'Admin',
            showLabel: showLabels,
            onTap: onAdmin!,
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
        if (showSuperAdminInline)
          FutureBuilder<bool>(
            future: RoleService.isSuperAdmin(),
            builder: (context, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return _TopBarAction(
                icon: Icons.library_books,
                label: 'Super Admin',
                showLabel: showLabels,
                onTap: onSuperAdmin,
              );
            },
          ),
        _TopBarAction(
          icon: Icons.manage_accounts,
          label: 'Account',
          showLabel: showLabels || medium,
          onTap: onAccount,
        ),
        if (!showLabels)
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'super_admin') onSuperAdmin();
              if (value == 'logout') onLogout();
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'super_admin',
                enabled: bundle?.isSuperAdmin == true,
                child: const Text('Super Admin'),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          )
        else ...[
          FutureBuilder<bool>(
            future: RoleService.isSuperAdmin(),
            builder: (context, snap) {
              if (snap.data != true || showSuperAdminInline) {
                return const SizedBox.shrink();
              }
              return _TopBarAction(
                icon: Icons.library_books,
                label: 'Super Admin',
                showLabel: true,
                onTap: onSuperAdmin,
              );
            },
          ),
          _TopBarAction(
            icon: Icons.logout,
            label: 'Logout',
            showLabel: true,
            onTap: onLogout,
          ),
        ],
        const SizedBox(width: 10),
      ],
    );
  }
}

class _TopBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool showLabel;
  final VoidCallback onTap;

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

class _UpcomingShowsEmptyState extends StatelessWidget {
  final bool showAdminButton;
  final VoidCallback onAdmin;

  const _UpcomingShowsEmptyState({
    required this.showAdminButton,
    required this.onAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: RMCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  size: 42,
                  color: AppColors.muted,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No upcoming shows yet',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  showAdminButton
                      ? 'Published shows will appear here once they are available. If you are a show secretary, open Admin to create or manage shows.'
                      : 'Published shows will appear here once they are available.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    if (showAdminButton)
                      FilledButton.icon(
                        onPressed: onAdmin,
                        icon: const Icon(Icons.admin_panel_settings),
                        label: const Text('Open Admin'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShowListBundle {
  final List<Map<String, dynamic>> shows;
  final List<Map<String, dynamic>> superAdminShows;
  final Set<String> adminShowIds;
  final bool isSuperAdmin;
  final bool hasAvailableShowCapacity;
  final bool hasAnyAssignedShows;

  _ShowListBundle({
    required this.shows,
    required this.superAdminShows,
    required this.adminShowIds,
    required this.isSuperAdmin,
    required this.hasAvailableShowCapacity,
    required this.hasAnyAssignedShows,
  });

  Set<String> get superAdminShowIds => superAdminShows
      .map((s) => (s['id'] ?? '').toString())
      .where((id) => id.isNotEmpty)
      .toSet();

  bool get canSeeAdminButton =>
      isSuperAdmin ||
      adminShowIds.isNotEmpty ||
      hasAvailableShowCapacity ||
      hasAnyAssignedShows;
}