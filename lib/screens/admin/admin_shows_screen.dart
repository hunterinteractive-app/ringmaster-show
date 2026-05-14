// lib/screens/admin/admin_shows_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_resources_screen.dart';

import '../show_list_screen.dart';
import '../create_show_screen.dart';
import 'edit_show_settings_screen.dart';
import '../../screens/my_animals_screen.dart';
import '../../screens/my_entries_screen.dart';
import '../../screens/account_settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../services/app_session.dart';
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageFuture = _loadPage();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_AdminShowsPageData> _loadPage() async {
    final shows = await _loadShows();
    final license = await _loadLicenseStatus();
    final entryCounts = await _loadEntryCounts(shows);

    return _AdminShowsPageData(
      shows: shows,
      license: license,
      entryCounts: entryCounts,
    );
  }

  Future<List<Map<String, dynamic>>> _loadShows() async {
    final userId = AppSession.effectiveUserId;
    if (userId == null) return [];

    final superAdminRes = AppSession.isSupportMode
        ? null
        : await supabase
            .from('super_admins')
            .select('user_id')
            .eq('user_id', userId)
            .maybeSingle();

    final isSuperAdmin = superAdminRes != null;

    final query = supabase.from('shows').select(
      'id,name,start_date,end_date,location_name,is_published,entry_open_at,entry_close_at,created_at,'
      'is_locked,locked_at,finalized_at',
    );

    final allowedShowIds = <String>{...widget.allowedShowIds};

    if (!isSuperAdmin) {
      try {
        final adminRows = await supabase
            .from('show_admins')
            .select('show_id')
            .eq('user_id', userId);

        for (final raw in (adminRows as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          final showId = row['show_id']?.toString();
          if (showId != null && showId.isNotEmpty) {
            allowedShowIds.add(showId);
          }
        }
      } catch (_) {
        // Keep using widget.allowedShowIds if the direct lookup fails.
      }
    }

    final res = isSuperAdmin
        ? await query.order('start_date').order('location_name')
        : allowedShowIds.isEmpty
            ? []
            : await query
                .inFilter('id', allowedShowIds.toList())
                .order('start_date')
                .order('location_name');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, _ShowEntryCounts>> _loadEntryCounts(
    List<Map<String, dynamic>> shows,
  ) async {
    if (shows.isEmpty) return {};

    final showIds = shows.map((s) => s['id'].toString()).toList();

    final rows = await supabase
        .from('show_sections')
        .select('''
          show_id,
          kind,
          letter,
          display_name,
          sort_order,
          entries!left(id)
        ''')
        .inFilter('show_id', showIds)
        .eq('is_enabled', true)
        .order('show_id')
        .order('sort_order');

    final countsByShow = <String, _ShowEntryCounts>{};

    for (final raw in (rows as List)) {
      final row = Map<String, dynamic>.from(raw as Map);

      final showId = row['show_id']?.toString();
      if (showId == null || showId.isEmpty) continue;

      final displayName = (row['display_name'] ?? '').toString().trim();
      if (displayName.isEmpty) continue;

      final kind = (row['kind'] ?? '').toString().trim();
      final letter = (row['letter'] ?? '').toString().trim();
      final sortOrder = (row['sort_order'] as num?)?.toInt() ?? 999999;

      final entriesRaw = row['entries'];
      final entryCount = entriesRaw is List ? entriesRaw.length : 0;

      final counts = countsByShow.putIfAbsent(showId, _ShowEntryCounts.new);
      counts.addCount(
        displayName,
        entryCount,
        kind: kind,
        letter: letter,
        sortOrder: sortOrder,
      );
    }

    for (final s in shows) {
      final showId = s['id'].toString();
      countsByShow.putIfAbsent(showId, _ShowEntryCounts.new);
    }

    return countsByShow;
  }

  Future<_ShowCreationStatus> _loadLicenseStatus() async {
    if (AppSession.isSupportMode) {
      return const _ShowCreationStatus(
        canCreate: false,
        remainingShowDays: 0,
        unlimitedActive: false,
        unlimitedExpiresAt: null,
        message: 'Support mode is read-only.',
      );
    }

    final userId = AppSession.effectiveUserId;
    if (userId == null) {
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
        params: {'p_user_id': userId},
      );

      if (result is List && result.isNotEmpty) {
        return _ShowCreationStatus.fromMap(
          Map<String, dynamic>.from(result.first as Map),
        );
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

  DateTime _showSortDate(Map<String, dynamic> show) {
    final start = DateTime.tryParse((show['start_date'] ?? '').toString());
    final created = DateTime.tryParse((show['created_at'] ?? '').toString());
    return start ?? created ?? DateTime(1900);
  }

  List<Map<String, dynamic>> _filteredAndSortedShows(
    List<Map<String, dynamic>> shows,
  ) {
    final q = _searchController.text.trim().toLowerCase();

    final filtered = shows.where((s) {
      if (q.isEmpty) return true;

      final published = s['is_published'] == true ? 'published' : 'draft';

      final haystack = [
        s['name'],
        s['location_name'],
        s['start_date'],
        s['end_date'],
        s['entry_open_at'],
        s['entry_close_at'],
        published,
      ].map((x) => (x ?? '').toString().toLowerCase()).join(' ');

      return haystack.contains(q);
    }).toList();

    filtered.sort((a, b) {
      final dateCmp = _showSortDate(a).compareTo(_showSortDate(b));
      if (dateCmp != 0) return dateCmp;

      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      final nameCmp = nameA.compareTo(nameB);
      if (nameCmp != 0) return nameCmp;

      final locA = (a['location_name'] ?? '').toString().toLowerCase();
      final locB = (b['location_name'] ?? '').toString().toLowerCase();
      return locA.compareTo(locB);
    });

    return filtered;
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
    if (AppSession.isSupportMode) return;
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

  void _openResources() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminResourcesScreen()),
    );
  }

  Widget _buildLicenseBanner(_ShowCreationStatus license) {
    final text = license.unlimitedActive
        ? 'Unlimited plan active${license.unlimitedExpiresAt == null ? '' : ' • Expires ${_fmtTs(license.unlimitedExpiresAt)}'}'
        : '${license.remainingShowDays} show day${license.remainingShowDays == 1 ? '' : 's'} remaining';

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

  Widget _buildShowCounts(_ShowEntryCounts counts) {
    return Wrap(
      spacing: 20,
      runSpacing: 10,
      children: [
        for (final sectionName in counts.orderedSectionNames)
          Text(
            '$sectionName: ${counts.bySection[sectionName] ?? 0}',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
        Text(
          'Grand Total All Active Sections: ${counts.grandTotal}',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AdminShowsPageData>(
      future: _pageFuture,
      builder: (context, snap) {
        final page = snap.data;
        final shows = _filteredAndSortedShows(page?.shows ?? const []);

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
            canCreate: !AppSession.isSupportMode &&
                license.canCreate &&
                snap.connectionState != ConnectionState.waiting,
            onShows: _openShows,
            onAnimals: _openAnimals,
            onEntries: _openEntries,
            onResources: _openResources,
            onAccount: _openAccount,
            onReload:
                snap.connectionState == ConnectionState.waiting ? null : _reload,
            onCreate: (AppSession.isSupportMode ||
                    snap.connectionState == ConnectionState.waiting ||
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
                          if (AppSession.isSupportMode) ...[
                            const SizedBox(height: AppSpacing.md),
                            RMCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Icon(Icons.support_agent, color: Colors.orange),
                                  SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text(
                                      'Support Mode — Admin shows are read-only. Creating shows is disabled.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          RMCard(
                            child: TextField(
                              controller: _searchController,
                              decoration: const InputDecoration(
                                labelText: 'Search shows',
                                hintText:
                                    'Show name, location, date, published, draft...',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (page?.hasAdminAccess != true)
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
                          else if (shows.isEmpty)
                            const Expanded(
                              child: RMEmptyState(
                                title: 'No matching shows',
                                subtitle: 'Try a different search term.',
                                icon: Icons.search_off,
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.builder(
                                itemCount: shows.length,
                                itemBuilder: (context, i) {
                                  final s = shows[i];

                                  final showId = s['id'].toString();
                                  final counts = page!.entryCounts[showId] ??
                                      _ShowEntryCounts();

                                  final name = (s['name'] ?? '').toString();
                                  final start = _fmtDate(
                                    (s['start_date'] ?? '').toString(),
                                  );
                                  final end = _fmtDate(
                                    (s['end_date'] ?? '').toString(),
                                  );
                                  final loc =
                                      (s['location_name'] ?? '').toString();
                                  final published = s['is_published'] == true;
                                  final isLocked = s['is_locked'] == true;
                                  final finalizedAt = (s['finalized_at'] ?? '').toString();
                                  final isFinalized = finalizedAt.isNotEmpty;

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
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                alignment: WrapAlignment.end,
                                                children: [
                                                  RMBadge(
                                                    text: published ? 'Published' : 'Draft',
                                                    icon: published ? Icons.public : Icons.edit_note,
                                                    success: published,
                                                  ),
                                                  if (isFinalized)
                                                    const RMBadge(
                                                      text: 'Finalized',
                                                      icon: Icons.verified,
                                                      success: true,
                                                    )
                                                  else if (isLocked)
                                                    const RMBadge(
                                                      text: 'Locked',
                                                      icon: Icons.lock,
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: AppSpacing.sm),
                                          Text(
                                            '$start${end != '—' ? ' → $end' : ''} • $loc',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppColors.muted,
                                                ),
                                          ),
                                          const SizedBox(height: AppSpacing.md),
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
                                          const SizedBox(height: AppSpacing.md),
                                          _buildShowCounts(counts),
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
  final VoidCallback onResources;
  final VoidCallback onAccount;
  final VoidCallback? onReload;
  final VoidCallback? onCreate;
  final bool canCreate;

  const _AdminShowsAppBar({
    required this.onShows,
    required this.onAnimals,
    required this.onEntries,
    required this.onResources,
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
    final showFullNav = width >= 900;

    return AppBar(
      toolbarHeight: 92,
      titleSpacing: 12,
      title: Row(
        children: [
          Image.asset(
            'assets/images/ringmaster_show_logo.png',
            height: width < 500 ? 38 : 48,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
          const SizedBox(width: 12),
          Flexible(
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
                        fontSize: width < 500 ? 20 : 28,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Admin Shows',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(.9),
                        fontSize: width < 500 ? 13 : 15,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: showFullNav
          ? [
              _TopBarAction(
                icon: Icons.refresh,
                label: 'Reload',
                showLabel: true,
                onTap: onReload,
              ),
              _TopBarAction(
                icon: Icons.add,
                label: 'Create Show',
                showLabel: true,
                onTap: onCreate,
              ),
              _TopBarAction(
                icon: Icons.event,
                label: 'Shows',
                showLabel: true,
                onTap: onShows,
              ),
              _TopBarAction(
                icon: Icons.pets,
                label: 'Animals',
                showLabel: true,
                onTap: onAnimals,
              ),
              _TopBarAction(
                icon: Icons.receipt_long,
                label: 'Entries',
                showLabel: true,
                onTap: onEntries,
              ),
              _TopBarAction(
                icon: Icons.perm_media_outlined,
                label: 'Resources',
                showLabel: true,
                onTap: onResources,
              ),
              _TopBarAction(
                icon: Icons.manage_accounts,
                label: 'Account',
                showLabel: true,
                onTap: onAccount,
              ),
              const SizedBox(width: 10),
            ]
          : [
              IconButton(
                tooltip: 'Reload',
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: onReload,
              ),
              IconButton(
                tooltip: 'Create Show',
                icon: const Icon(Icons.add, color: Colors.white),
                onPressed: onCreate,
              ),
              PopupMenuButton<String>(
                tooltip: 'Menu',
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  switch (value) {
                    case 'shows':
                      onShows();
                      break;
                    case 'animals':
                      onAnimals();
                      break;
                    case 'entries':
                      onEntries();
                      break;
                    case 'resources':
                      onResources();
                      break;
                    case 'account':
                      onAccount();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'shows',
                    child: ListTile(
                      leading: Icon(Icons.event),
                      title: Text('Shows'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'animals',
                    child: ListTile(
                      leading: Icon(Icons.pets),
                      title: Text('Animals'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'entries',
                    child: ListTile(
                      leading: Icon(Icons.receipt_long),
                      title: Text('Entries'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'resources',
                    child: ListTile(
                      leading: Icon(Icons.perm_media_outlined),
                      title: Text('Resources'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'account',
                    child: ListTile(
                      leading: Icon(Icons.manage_accounts),
                      title: Text('Account'),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
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
  final Map<String, _ShowEntryCounts> entryCounts;

  const _AdminShowsPageData({
    required this.shows,
    required this.license,
    required this.entryCounts,
  });

  bool get hasAdminAccess => shows.isNotEmpty;
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

class _ShowEntryCounts {
  final Map<String, int> bySection;
  final Map<String, _SectionMeta> metaBySection;

  _ShowEntryCounts({
    Map<String, int>? bySection,
    Map<String, _SectionMeta>? metaBySection,
  })  : bySection = bySection ?? <String, int>{},
        metaBySection = metaBySection ?? <String, _SectionMeta>{};

  int get grandTotal =>
      bySection.values.fold(0, (sum, value) => sum + value);

  void addCount(
    String sectionName,
    int count, {
    required String kind,
    required String letter,
    required int sortOrder,
  }) {
    bySection[sectionName] = (bySection[sectionName] ?? 0) + count;
    metaBySection.putIfAbsent(
      sectionName,
      () => _SectionMeta(
        name: sectionName,
        kind: kind,
        letter: letter,
        sortOrder: sortOrder,
      ),
    );
  }

  List<String> get orderedSectionNames {
    final names = bySection.keys.toList();

    names.sort((a, b) {
      final am = metaBySection[a]!;
      final bm = metaBySection[b]!;

      final aRank = am.displayRank;
      final bRank = bm.displayRank;
      if (aRank != bRank) return aRank.compareTo(bRank);

      final aLetterRank = am.letterRank;
      final bLetterRank = bm.letterRank;
      if (aLetterRank != bLetterRank) {
        return aLetterRank.compareTo(bLetterRank);
      }

      if (am.sortOrder != bm.sortOrder) {
        return am.sortOrder.compareTo(bm.sortOrder);
      }

      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    return names;
  }
}

class _SectionMeta {
  final String name;
  final String kind;
  final String letter;
  final int sortOrder;

  const _SectionMeta({
    required this.name,
    required this.kind,
    required this.letter,
    required this.sortOrder,
  });

  int get displayRank {
    final k = kind.toLowerCase().trim();
    if (k == 'open') return 0;
    if (k == 'youth') return 1;
    return 2;
  }

  int get letterRank {
    final l = letter.toUpperCase().trim();
    if (l.isEmpty) return 999;

    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final idx = letters.indexOf(l);
    if (idx >= 0) return idx;

    return 999;
  }
}