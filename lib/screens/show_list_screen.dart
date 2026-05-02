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

import '../config/legal_config.dart';
import '../services/role_service.dart';
import '../utils/date_time_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/rm_widgets.dart';
import '../widgets/rm_timezone_notice_banner.dart';

final supabase = Supabase.instance.client;

class ShowListScreen extends StatefulWidget {
  const ShowListScreen({super.key});

  @override
  State<ShowListScreen> createState() => _ShowListScreenState();
}

class _ShowListScreenState extends State<ShowListScreen> {
  final TextEditingController _searchController = TextEditingController();

  late Future<_ShowListBundle> _bundleFuture;

  String _searchQuery = '';
  String _sortMode = 'date';
  String _stateFilter = 'All';
  bool _checkingLegal = false;

  static const Map<String, String> _stateAbbreviationToName = {
    'AL': 'Alabama',
    'AK': 'Alaska',
    'AZ': 'Arizona',
    'AR': 'Arkansas',
    'CA': 'California',
    'CO': 'Colorado',
    'CT': 'Connecticut',
    'DE': 'Delaware',
    'FL': 'Florida',
    'GA': 'Georgia',
    'HI': 'Hawaii',
    'ID': 'Idaho',
    'IL': 'Illinois',
    'IN': 'Indiana',
    'IA': 'Iowa',
    'KS': 'Kansas',
    'KY': 'Kentucky',
    'LA': 'Louisiana',
    'ME': 'Maine',
    'MD': 'Maryland',
    'MA': 'Massachusetts',
    'MI': 'Michigan',
    'MN': 'Minnesota',
    'MS': 'Mississippi',
    'MO': 'Missouri',
    'MT': 'Montana',
    'NE': 'Nebraska',
    'NV': 'Nevada',
    'NH': 'New Hampshire',
    'NJ': 'New Jersey',
    'NM': 'New Mexico',
    'NY': 'New York',
    'NC': 'North Carolina',
    'ND': 'North Dakota',
    'OH': 'Ohio',
    'OK': 'Oklahoma',
    'OR': 'Oregon',
    'PA': 'Pennsylvania',
    'RI': 'Rhode Island',
    'SC': 'South Carolina',
    'SD': 'South Dakota',
    'TN': 'Tennessee',
    'TX': 'Texas',
    'UT': 'Utah',
    'VT': 'Vermont',
    'VA': 'Virginia',
    'WA': 'Washington',
    'WV': 'West Virginia',
    'WI': 'Wisconsin',
    'WY': 'Wyoming',
    'DC': 'District of Columbia',
  };

  static final Map<String, String> _stateNameLookup = {
    for (final entry in _stateAbbreviationToName.entries)
      entry.value.toUpperCase(): entry.value,
  };

  @override
  void initState() {
    super.initState();
    _bundleFuture = Future.value(
      _ShowListBundle(
        shows: [],
        superAdminShows: [],
        adminShowIds: {},
        isSuperAdmin: false,
        hasAvailableShowCapacity: false,
        hasAnyAssignedShows: false,
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  String _extractState(String location) {
    final raw = location.trim();
    if (raw.isEmpty) return '';

    final upper = raw.toUpperCase();

    // Look for ", ST 12345" or ", ST" or " ST 12345"
    final abbrPattern = RegExp(
      r'(?:^|,|\s)([A-Z]{2})(?=\s+\d{5}(?:-\d{4})?$|$)',
    );
    for (final match in abbrPattern.allMatches(upper)) {
      final abbr = match.group(1);
      if (abbr != null && _stateAbbreviationToName.containsKey(abbr)) {
        return _stateAbbreviationToName[abbr]!;
      }
    }

    // Look for full state names anywhere in the string, longest first
    final stateNames = _stateNameLookup.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final upperStateName in stateNames) {
      final pattern = RegExp(
        r'(^|[^A-Z])' + RegExp.escape(upperStateName) + r'([^A-Z]|$)',
      );
      if (pattern.hasMatch(upper)) {
        return _stateNameLookup[upperStateName]!;
      }
    }

    // Fallback: inspect comma-separated parts from right to left
    final parts = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList()
        .reversed;

    for (final part in parts) {
      final partUpper = part.toUpperCase();

      final firstTokenMatch =
          RegExp(r'^([A-Z]{2})(?:\s|$)').firstMatch(partUpper);
      if (firstTokenMatch != null) {
        final abbr = firstTokenMatch.group(1)!;
        if (_stateAbbreviationToName.containsKey(abbr)) {
          return _stateAbbreviationToName[abbr]!;
        }
      }

      if (_stateNameLookup.containsKey(partUpper)) {
        return _stateNameLookup[partUpper]!;
      }
    }

    return '';
  }

  DateTime? _parseDate(String raw) {
    if (raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  List<String> _availableStates(List<Map<String, dynamic>> shows) {
    final values = shows
        .map((s) => _extractState((s['location_name'] ?? '').toString()))
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return ['All', ...values];
  }

  List<Map<String, dynamic>> _applyFiltersAndSort(
    List<Map<String, dynamic>> shows,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = shows.where((s) {
      final name = (s['name'] ?? '').toString();
      final location = (s['location_name'] ?? '').toString();
      final state = _extractState(location);
      final startDate = (s['start_date'] ?? '').toString();

      final matchesState = _stateFilter == 'All' || state == _stateFilter;

      final haystack = [
        name,
        location,
        state,
        startDate,
      ].join(' ').toLowerCase();

      final matchesSearch = query.isEmpty || haystack.contains(query);

      return matchesState && matchesSearch;
    }).toList();

    filtered.sort((a, b) {
      final aDate = _parseDate((a['start_date'] ?? '').toString());
      final bDate = _parseDate((b['start_date'] ?? '').toString());
      final aState = _extractState((a['location_name'] ?? '').toString());
      final bState = _extractState((b['location_name'] ?? '').toString());
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();

      if (_sortMode == 'state') {
        final stateCmp = aState.compareTo(bState);
        if (stateCmp != 0) return stateCmp;

        if (aDate != null && bDate != null) {
          final dateCmp = aDate.compareTo(bDate);
          if (dateCmp != 0) return dateCmp;
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }

        return aName.compareTo(bName);
      }

      // Default: show date, then state alphabetically, then show name
      if (aDate != null && bDate != null) {
        final dateCmp = aDate.compareTo(bDate);
        if (dateCmp != 0) return dateCmp;
      } else if (aDate != null) {
        return -1;
      } else if (bDate != null) {
        return 1;
      }

      final stateCmp = aState.compareTo(bState);
      if (stateCmp != 0) return stateCmp;

      return aName.compareTo(bName);
    });

    return filtered;
  }

  Future<void> _verifyLegalAcceptance() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }

    final profile = await supabase
        .from('profiles')
        .select('accepted_terms_version, accepted_privacy_version')
        .eq('id', user.id)
        .maybeSingle();

    final termsOk =
        profile?['accepted_terms_version'] == LegalConfig.currentTermsVersion;
    final privacyOk =
        profile?['accepted_privacy_version'] == LegalConfig.currentPrivacyVersion;

    if (termsOk && privacyOk) {
      if (!mounted) return;
      setState(() {
        _bundleFuture = _loadBundle();
        _checkingLegal = false;
      });
      return;
    }

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
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
    if (_checkingLegal) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return FutureBuilder<_ShowListBundle>(
      future: _bundleFuture,
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
                MaterialPageRoute(
                  builder: (_) => const AccountSettingsScreen(),
                ),
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
                final allShows = bundle.shows;
                final stateOptions = _availableStates(allShows);
                final shows = _applyFiltersAndSort(allShows);

                if (allShows.isEmpty) {
                  content = _UpcomingShowsEmptyState(
                    showAdminButton: bundle.canSeeAdminButton,
                    onAdmin: () => _openAdmin(context, bundle),
                  );
                } else {
                  content = LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 700;
                      final horizontalPadding =
                          isMobile ? AppSpacing.md : AppSpacing.lg;

                      return Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              0,
                              horizontalPadding,
                              AppSpacing.md,
                            ),
                            child: RMCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      labelText: 'Search shows',
                                      hintText: isMobile
                                          ? 'Search name, location, state, date'
                                          : 'Search by show name, location, state, or date',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: _searchQuery.isEmpty
                                          ? null
                                          : IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                setState(() {
                                                  _searchController.clear();
                                                  _searchQuery = '';
                                                });
                                              },
                                            ),
                                      border: const OutlineInputBorder(),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _searchQuery = value;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Wrap(
                                    spacing: AppSpacing.md,
                                    runSpacing: AppSpacing.md,
                                    children: [
                                      SizedBox(
                                        width: isMobile
                                            ? constraints.maxWidth
                                            : 220,
                                        child: DropdownButtonFormField<String>(
                                          value: _sortMode,
                                          decoration: const InputDecoration(
                                            labelText: 'Sort by',
                                            border: OutlineInputBorder(),
                                          ),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'date',
                                              child: Text('Show Date'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'state',
                                              child: Text('State'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() {
                                              _sortMode = value;
                                            });
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: isMobile
                                            ? constraints.maxWidth
                                            : 220,
                                        child: DropdownButtonFormField<String>(
                                          value:
                                              stateOptions.contains(_stateFilter)
                                                  ? _stateFilter
                                                  : 'All',
                                          decoration: const InputDecoration(
                                            labelText: 'Filter by State',
                                            border: OutlineInputBorder(),
                                          ),
                                          items: stateOptions
                                              .map(
                                                (state) =>
                                                    DropdownMenuItem<String>(
                                                  value: state,
                                                  child: Text(state),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() {
                                              _stateFilter = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    '${shows.length} show${shows.length == 1 ? '' : 's'} found',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: shows.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.xl),
                                      child: Text(
                                        'No shows match your current search or filters.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: EdgeInsets.fromLTRB(
                                      horizontalPadding,
                                      0,
                                      horizontalPadding,
                                      AppSpacing.xl,
                                    ),
                                    itemCount: shows.length,
                                    itemBuilder: (context, i) {
                                      final s = shows[i];
                                      final showId = s['id'].toString();
                                      final showName =
                                          (s['name'] ?? '').toString();
                                      final location =
                                          (s['location_name'] ?? '').toString();

                                      final formattedStartDate =
                                          formatLocalDateTime(
                                        s['start_date']?.toString(),
                                      );

                                      final entryDeadlineText =
                                          formatLocalDateTime(
                                        s['entry_close_at']?.toString(),
                                      );

                                      final deadlinePassed =
                                          s['entry_close_at'] != null &&
                                              DateTime.parse(
                                                s['entry_close_at'].toString(),
                                              )
                                                  .toLocal()
                                                  .isBefore(DateTime.now());

                                      final isAdminForShow =
                                          bundle.isSuperAdmin ||
                                              bundle.adminShowIds
                                                  .contains(showId);

                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpacing.md,
                                        ),
                                        child: RMCard(
                                          onTap: () => _openEnterShow(
                                            context,
                                            showId,
                                            showName,
                                          ),
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
                                                      showName,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    tooltip: 'Actions',
                                                    onSelected: (v) {
                                                      if (v == 'enter') {
                                                        _openEnterShow(
                                                          context,
                                                          showId,
                                                          showName,
                                                        );
                                                      } else if (v == 'admin') {
                                                        _openEditShow(
                                                          context,
                                                          showId,
                                                        );
                                                      }
                                                    },
                                                    itemBuilder: (_) => [
                                                      const PopupMenuItem(
                                                        value: 'enter',
                                                        child:
                                                            Text('Enter Show'),
                                                      ),
                                                      if (isAdminForShow)
                                                        const PopupMenuItem(
                                                          value: 'admin',
                                                          child: Text(
                                                            'Admin Settings',
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.sm,
                                              ),
                                              Text(
                                                '$formattedStartDate • $location',
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
                                                      icon: Icons
                                                          .admin_panel_settings,
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