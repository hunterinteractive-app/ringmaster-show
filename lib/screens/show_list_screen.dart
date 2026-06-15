// lib/screens/show_list_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ringmaster_show/screens/admin/admin_shows_screen.dart';
import 'package:ringmaster_show/screens/admin/edit_show_settings_screen.dart';
import 'package:ringmaster_show/screens/admin/entries_by_breed_section_table.dart';


import 'package:ringmaster_show/widgets/help_report_dialog.dart';
import 'package:ringmaster_show/widgets/my_help_requests_button.dart';


import 'login_screen.dart';
import 'my_animals_screen.dart';
import 'enter_show_screen.dart';
import 'account_settings_screen.dart';
import 'my_entries_screen.dart';
import 'legal/terms_screen.dart';
import 'legal/privacy_policy_screen.dart';
import 'super_admin/superadmin_home_screen.dart';
import 'package:ringmaster_show/superintendent/superintendent_shows_screen.dart';
import 'account_profile_setup_screen.dart';

import '../config/legal_config.dart';
import '../services/app_session.dart';
import '../services/role_service.dart';
import '../services/stripe_connect_service.dart';
import '../utils/date_time_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/rm_widgets.dart';
import '../widgets/rm_timezone_notice_banner.dart';

final supabase = Supabase.instance.client;

class ShowListScreen extends StatefulWidget {
  const ShowListScreen({
    super.key,
    this.demoMode = false,
    this.demoSecretaryMode = false,
  });

  final bool demoMode;
  final bool demoSecretaryMode;

  @override
  State<ShowListScreen> createState() => _ShowListScreenState();
}

class _ShowListScreenState extends State<ShowListScreen> {
  final TextEditingController _searchController = TextEditingController();

  late Future<_ShowListBundle> _bundleFuture;

  String _searchQuery = '';
  String _sortMode = 'date';
  String _stateFilter = 'All';
  bool _showSearchFilters = true;
  bool _checkingLegal = true;
  bool _canAccessAdmin = false;
  bool _canAccessSuperintendent = false;
  bool _loadingAdminAccess = true;
  bool _resolvingExhibitorAccount = false;
  // Temporary feature flag. Change to true when superintendent-role access
  // is ready to be released.
  static const bool _enableSuperintendentRoleAccess = false;
  Future<bool> _ensureExhibitorAccount() async {
    if (widget.demoMode || SupportImpersonationSession.isActive) {
      return true;
    }

    if (_resolvingExhibitorAccount) return false;

    final user = supabase.auth.currentUser;
    if (user == null) return false;

    _resolvingExhibitorAccount = true;

    try {
      final response = await supabase.functions.invoke(
        'claim-or-import-exhibitor',
        body: const {'action': 'lookup'},
      );

      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};

      final status = (data['status'] ?? '').toString();

      switch (status) {
        case 'already_exists':
        case 'imported':
        case 'claimed':
          return true;

        case 'claim_confirmation_required':
          final match = data['match'] is Map
              ? Map<String, dynamic>.from(data['match'] as Map)
              : <String, dynamic>{};

          final shouldClaim = await _showClaimConfirmationDialog(match);
          if (!shouldClaim) {
            return await _openManualAccountSetup();
          }

          final exhibitorId = (match['id'] ?? '').toString();
          if (exhibitorId.isEmpty) {
            return await _openManualAccountSetup();
          }

          return await _claimExhibitor(exhibitorId);

        case 'multiple_unclaimed_matches':
          final rawMatches = data['matches'];
          final matches = rawMatches is List
              ? rawMatches
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
              : <Map<String, dynamic>>[];

          final selectedId = await _showMultipleClaimDialog(matches);
          if (selectedId == null) {
            return await _openManualAccountSetup();
          }

          return await _claimExhibitor(selectedId);

        case 'club_not_found':
        case 'club_multiple_matches':
        case 'incomplete_club_match':
          return await _openManualAccountSetup();

        default:
          throw Exception(
            (data['message'] ??
                    'Unable to verify or import your exhibitor account.')
                .toString(),
          );
      }
    } catch (error) {
      if (!mounted) return false;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Unable to Set Up Account'),
            content: Text(
              'RingMaster Show could not verify, claim, or import your '
              'account information.\n\n$error',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Try Manual Setup'),
              ),
            ],
          );
        },
      );

      return await _openManualAccountSetup();
    } finally {
      _resolvingExhibitorAccount = false;
    }
  }

  Future<bool> _claimExhibitor(String exhibitorId) async {
    final response = await supabase.functions.invoke(
      'claim-or-import-exhibitor',
      body: {
        'action': 'claim',
        'exhibitor_id': exhibitorId,
      },
    );

    final data = response.data is Map
        ? Map<String, dynamic>.from(response.data as Map)
        : <String, dynamic>{};

    final status = (data['status'] ?? '').toString();

    if (status == 'claimed' || status == 'already_exists') {
      return true;
    }

    if (status == 'claim_unavailable') {
      if (!mounted) return false;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That exhibitor record is no longer available to claim.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );

      return await _openManualAccountSetup();
    }

    throw Exception(
      (data['message'] ?? 'Unable to claim the exhibitor record.').toString(),
    );
  }

  Future<bool> _openManualAccountSetup() async {
    if (!mounted) return false;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AccountProfileSetupScreen(),
      ),
    );

    return saved == true;
  }

  Future<bool> _showClaimConfirmationDialog(
    Map<String, dynamic> match,
  ) async {
    final displayName = (match['display_name'] ?? 'this exhibitor').toString();
    final city = (match['city'] ?? '').toString().trim();
    final state = (match['state'] ?? '').toString().trim();
    final phoneLastFour = (match['phone_last_four'] ?? '').toString().trim();

    final location = [city, state]
        .where((value) => value.isNotEmpty)
        .join(', ');

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Existing Exhibitor Record Found'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A show secretary previously created an exhibitor record '
                    'for $displayName.',
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Location: $location'),
                  ],
                  if (phoneLastFour.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Phone ending in $phoneLastFour'),
                  ],
                  const SizedBox(height: 12),
                  const Text('Is this your exhibitor account?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('No, Create New'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Yes, Link Account'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<String?> _showMultipleClaimDialog(
    List<Map<String, dynamic>> matches,
  ) async {
    if (matches.isEmpty) return null;

    String? selectedId;

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Your Exhibitor Record'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: matches.map((match) {
                      final id = (match['id'] ?? '').toString();
                      final name =
                          (match['display_name'] ?? 'Unnamed exhibitor')
                              .toString();
                      final city = (match['city'] ?? '').toString().trim();
                      final state = (match['state'] ?? '').toString().trim();
                      final phone =
                          (match['phone_last_four'] ?? '').toString().trim();

                      final details = <String>[
                        if (city.isNotEmpty || state.isNotEmpty)
                          [city, state]
                              .where((value) => value.isNotEmpty)
                              .join(', '),
                        if (phone.isNotEmpty) 'Phone ending in $phone',
                      ].join(' • ');

                      return RadioListTile<String>(
                        value: id,
                        groupValue: selectedId,
                        title: Text(name),
                        subtitle: details.isEmpty ? null : Text(details),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedId = value;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Create New Instead'),
                ),
                FilledButton(
                  onPressed: selectedId == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(selectedId),
                  child: const Text('Link Selected Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  SupportImpersonatedUser? get _impersonatedUser =>
      SupportImpersonationSession.current.value;

  String? get _effectiveUserId => AppSession.effectiveUserId;

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

  Future<bool> _loadSuperintendentAccessFlag() async {
    if (widget.demoMode || SupportImpersonationSession.isActive) {
      return false;
    }

    final userId = _effectiveUserId;
    if (userId == null) return false;

    try {
      if (await RoleService.isSuperAdmin()) {
        return true;
      }

      if (!_enableSuperintendentRoleAccess) {
        return false;
      }

      final roleRow = await supabase
          .from('role_assignments')
          .select('show_id')
          .eq('user_id', userId)
          .eq('role', 'superintendent')
          .limit(1);

      return (roleRow as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadAdminAccess() async {
    final user = supabase.auth.currentUser;
    final effectiveUserId = _effectiveUserId;

    if (user == null || effectiveUserId == null || widget.demoMode) {
      if (!mounted) return;
      setState(() {
        _canAccessAdmin = false;
        _canAccessSuperintendent = false;
        _loadingAdminAccess = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loadingAdminAccess = true;
        _canAccessAdmin = false;
        _canAccessSuperintendent = false;
      });
    }

    var canAdmin = false;
    var canSuperintendent = false;

    try {
      final roleRows = await supabase
          .from('role_assignments')
          .select('show_id')
          .eq('user_id', effectiveUserId)
          .inFilter('role', const [
            'super_admin',
            'admin',
            'show_admin',
            'superintendent',
            'reporting_clerk',
          ])
          .limit(1);

      final showAdminRows = await supabase
          .from('show_admins')
          .select('show_id')
          .eq('user_id', effectiveUserId)
          .limit(1);

      canAdmin = (roleRows as List).isNotEmpty ||
          (showAdminRows as List).isNotEmpty;
    } catch (_) {
      canAdmin = false;
    }

    try {
      canSuperintendent = await _loadSuperintendentAccessFlag();
    } catch (_) {
      canSuperintendent = false;
    }

    if (!mounted) return;

    setState(() {
      _canAccessAdmin = canAdmin;
      _canAccessSuperintendent = canSuperintendent;
      _loadingAdminAccess = false;
    });
  }

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
    _verifyLegalAcceptance();
    SupportImpersonationSession.current.addListener(_handleSupportModeChanged);
  }

  @override
  void dispose() {
    SupportImpersonationSession.current.removeListener(
      _handleSupportModeChanged,
    );
    _searchController.dispose();
    super.dispose();
  }
  
  void _handleSupportModeChanged() {
    if (!mounted) return;
    _loadAdminAccess();
    setState(() {
      _bundleFuture = _loadBundle();
    });
  }

  Future<List<Map<String, dynamic>>> _loadShows() async {
    final query = supabase
        .from('shows')
        .select('id,name,start_date,location_name,entry_close_at,is_demo,demo_resets_at');

    if (widget.demoMode) {
      final res = await query
          .eq('id', '0f432fe8-2be2-467a-842f-ff3777436992')
          .limit(1);

      return (res as List).cast<Map<String, dynamic>>();
    }

    final now = DateTime.now().toUtc().toIso8601String();

    final res = await query
        .eq('is_published', true)
        .or('entry_close_at.is.null,entry_close_at.gte.$now')
        .order('start_date');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Set<String>> _loadAdminShowIds() async {
    final userId = _effectiveUserId;
    if (userId == null) return <String>{};

    if (widget.demoMode && !widget.demoSecretaryMode) {
      return <String>{};
    }

    final allowedShowIds = <String>{};

    try {
      final roleRows = await supabase
          .from('role_assignments')
          .select('show_id, role')
          .eq('user_id', userId);

      const allowedRoles = {
        'super_admin',
        'admin',
        'show_admin',
        'superintendent',
        'reporting_clerk',
      };

      allowedShowIds.addAll(
        (roleRows as List)
            .cast<Map<String, dynamic>>()
            .where((r) => allowedRoles.contains((r['role'] ?? '').toString()))
            .map((r) => (r['show_id'] ?? '').toString())
            .where((id) => id.isNotEmpty),
      );
    } catch (_) {
      // Older demo/admin records may not exist in role_assignments.
    }

    try {
      final adminRows = await supabase
          .from('show_admins')
          .select('show_id')
          .eq('user_id', userId);

      allowedShowIds.addAll(
        (adminRows as List)
            .cast<Map<String, dynamic>>()
            .map((r) => (r['show_id'] ?? '').toString())
            .where((id) => id.isNotEmpty),
      );
    } catch (_) {
      // Keep any role_assignments results if show_admins lookup fails.
    }

    if (widget.demoMode && widget.demoSecretaryMode) {
      allowedShowIds.add('0f432fe8-2be2-467a-842f-ff3777436992');
    }

    return allowedShowIds;
  }

  Future<bool> _hasAnyAssignedShows() async {
    final userId = _effectiveUserId;
    if (userId == null) return false;

    final rows = await supabase
        .from('role_assignments')
        .select('show_id')
        .eq('user_id', userId)
        .limit(1);

    return (rows as List).isNotEmpty;
  }

  Future<bool> _hasAvailableShowCapacity() async {
    final userId = _effectiveUserId;
    if (userId == null) return false;

    final row = await supabase
        .from('account_license_balances')
        .select(
          'purchased_show_days, consumed_show_days, unlimited_access, unlimited_active',
        )
        .eq('user_id', userId)
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
    final isSupportMode = SupportImpersonationSession.isActive;
    final realUserIsSuperAdmin = widget.demoMode
        ? false
        : await RoleService.isSuperAdmin();
    final isSuper = !isSupportMode && realUserIsSuperAdmin;

    List<Map<String, dynamic>> superAdminShows = <Map<String, dynamic>>[];
    if (isSuper || (isSupportMode && realUserIsSuperAdmin)) {
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
    if (widget.demoMode && widget.demoSecretaryMode) {
      hasAvailableShowCapacity = true;
    } else if (!widget.demoMode) {
      try {
        hasAvailableShowCapacity = await _hasAvailableShowCapacity();
      } catch (_) {
        hasAvailableShowCapacity = false;
      }
    }

    bool hasAnyAssignedShows = false;
    if (!widget.demoMode) {
      try {
        hasAnyAssignedShows = await _hasAnyAssignedShows();
      } catch (_) {
        hasAnyAssignedShows = false;
      }
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

  String? _formatDemoResetText(List<Map<String, dynamic>> shows) {
    if (shows.isEmpty) return null;

    final raw = shows.first['demo_resets_at']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;

    final resetAt = DateTime.tryParse(raw)?.toLocal();
    if (resetAt == null) return null;

    final remaining = resetAt.difference(DateTime.now());
    if (remaining.isNegative) return 'soon';

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);

    if (hours <= 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
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
    if (widget.demoMode) {
      if (!mounted) return;
      setState(() {
        _canAccessAdmin = false;
        _loadingAdminAccess = false;
        _bundleFuture = _loadBundle();
        _checkingLegal = false;
      });
      return;
    }

    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }

    final userId = _effectiveUserId ?? user.id;

    if (SupportImpersonationSession.isActive) {
      await _loadAdminAccess();
      if (!mounted) return;
      setState(() {
        _bundleFuture = _loadBundle();
        _checkingLegal = false;
      });
      return;
    }

    final profile = await supabase
        .from('profiles')
        .select('accepted_terms_version, accepted_privacy_version')
        .eq('user_id', userId)
        .maybeSingle();

    final termsOk =
        profile?['accepted_terms_version'] == LegalConfig.currentTermsVersion;
    final privacyOk =
        profile?['accepted_privacy_version'] == LegalConfig.currentPrivacyVersion;

    if (termsOk && privacyOk) {
      final accountReady = await _ensureExhibitorAccount();
      if (!accountReady || !mounted) return;

      await _loadAdminAccess();
      if (!mounted) return;
      setState(() {
        _bundleFuture = _loadBundle();
        _checkingLegal = false;
      });
      return;
    }

    if (!mounted) return;

    final agreed = await _showLegalAgreementDialog();

    if (!agreed) {
      await supabase.auth.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }

    try {
      await supabase.from('profiles').upsert({
        'user_id': userId,
        'accepted_terms_version': LegalConfig.currentTermsVersion,
        'accepted_terms_at': DateTime.now().toUtc().toIso8601String(),
        'accepted_privacy_version': LegalConfig.currentPrivacyVersion,
        'accepted_privacy_at': DateTime.now().toUtc().toIso8601String(),
        'email': user.email,
        'display_name': user.email?.split('@').first ?? 'User',
      }, onConflict: 'user_id');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save legal agreement: $e'),
          backgroundColor: AppColors.danger,
        ),
      );

      return;
    }

    if (!mounted) return;

    final accountReady = await _ensureExhibitorAccount();
    if (!accountReady || !mounted) return;

    await _loadAdminAccess();
    if (!mounted) return;
    setState(() {
      _bundleFuture = _loadBundle();
      _checkingLegal = false;
    });
  }

  Future<bool> _showLegalAgreementDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            bool checked = false;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Terms & Privacy Agreement'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Our Terms of Service or Privacy Policy have changed. '
                          'Please review and agree before continuing.',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TermsScreen(),
                                  ),
                                );
                              },
                              child: const Text('View Terms of Service'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const PrivacyPolicyScreen(),
                                  ),
                                );
                              },
                              child: const Text('View Privacy Policy'),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        CheckboxListTile(
                          value: checked,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'I have reviewed and agree to the current Terms of Service and Privacy Policy.',
                          ),
                          onChanged: (value) {
                            setState(() => checked = value ?? false);
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: checked
                          ? () => Navigator.pop(context, true)
                          : null,
                      child: const Text('Agree & Continue'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;
  }

  Future<void> _logout(BuildContext context) async {
    await supabase.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _exitSupportMode() {
    SupportImpersonationSession.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support mode ended.')),
    );
    _loadAdminAccess();
    setState(() {
      _bundleFuture = _loadBundle();
    });
  }

  void _openAdmin(BuildContext context, _ShowListBundle bundle) {
    final allowedShowIds = SupportImpersonationSession.isActive &&
            bundle.superAdminShowIds.isNotEmpty
        ? bundle.superAdminShowIds.toList()
        : bundle.isSuperAdmin
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
    if (SupportImpersonationSession.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry is disabled while viewing in support mode.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EnterShowScreen(
          showId: showId,
          showName: showName,
        ),
      ),
    ).then((_) {
      if (!mounted) return;
      if (widget.demoMode) {
        setState(() {
          _bundleFuture = _loadBundle();
        });
      }
    });
  }

  void _openBreedCounts(BuildContext context, String showId, String showName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('Breed Counts - $showName'),
          ),
          body: EntriesByBreedSectionTable(
            showId: showId,
            showName: showName,
            includeScratched: false,
            showExportButton: false,
            showExhibitorCounts: true,
            title: 'Breed Counts',
          ),
        ),
      ),
    );
  }

  Future<void> _showPaymentInfo(
    BuildContext context,
    String showId,
    String showName,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 14),
            Expanded(child: Text('Checking payment setup...')),
          ],
        ),
      ),
    );

    bool payOnline = false;
    String? error;

    try {
      final status = await StripeConnectService.getAccountStatus(showId);
      payOnline = status['charges_enabled'] == true &&
          status['payouts_enabled'] == true &&
          status['details_submitted'] == true;
    } catch (e) {
      error = e.toString();
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(showName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  payOnline ? Icons.credit_card : Icons.payments_outlined,
                  color: payOnline ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    payOnline ? 'Payment: Pay Online' : 'Payment: Paid at Show',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Online payment not setup, so this show is paid at show.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
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
            showAdmin: !_loadingAdminAccess &&
                (_canAccessAdmin ||
                    (bundle?.canSeeAdminButton ?? false) ||
                    (SupportImpersonationSession.isActive &&
                        (bundle?.superAdminShowIds.isNotEmpty ?? false))),
            onAdmin: bundle == null ? null : () => _openAdmin(context, bundle),
            showSuperintendent: !_loadingAdminAccess &&
                !SupportImpersonationSession.isActive &&
                (bundle?.isSuperAdmin == true || _canAccessSuperintendent),
            onSuperintendent: bundle == null
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SuperintendentShowsScreen(),
                      ),
                    );
                  },
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
              ).then((_) {
                if (!mounted) return;
                setState(() {
                  _bundleFuture = _loadBundle();
                });
              });
            },
            onAccount: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AccountSettingsScreen(),
                ),
              );
            },
            onHelp: () => showDialog<void>(
              context: context,
              builder: (_) => HelpReportDialog(
                pageTitle: widget.demoMode
                    ? 'Demo Mode — RingMaster Show'
                    : 'Upcoming Shows',
                pageRoute: ModalRoute.of(context)?.settings.name,
              ),
            ),
            onLogout: () => _logout(context),
            demoMode: widget.demoMode,
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
                    showAdminButton: !_loadingAdminAccess &&
                        (_canAccessAdmin ||
                            bundle.canSeeAdminButton ||
                            (SupportImpersonationSession.isActive &&
                                bundle.superAdminShowIds.isNotEmpty)),
                    onAdmin: () => _openAdmin(context, bundle),
                  );
                } else {
                  content = LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 700;
                      final horizontalPadding =
                          isMobile ? AppSpacing.md : AppSpacing.lg;

                      return SingleChildScrollView(
                        child: Column(
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
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Search Shows',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _showSearchFilters = !_showSearchFilters;
                                            });
                                          },
                                          icon: Icon(
                                            _showSearchFilters
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                          ),
                                          label: Text(_showSearchFilters ? 'Hide' : 'Show'),
                                        ),
                                      ],
                                    ),
                                    if (_showSearchFilters) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      TextField(
                                        controller: _searchController,
                                        decoration: InputDecoration(
                                          labelText: 'Search shows',
                                          prefixIcon: const Icon(Icons.search),
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
                                            width: isMobile ? double.infinity : 220,
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
                                            width: isMobile ? double.infinity : 220,
                                            child: DropdownButtonFormField<String>(
                                              value: stateOptions.contains(_stateFilter)
                                                  ? _stateFilter
                                                  : 'All',
                                              decoration: const InputDecoration(
                                                labelText: 'Filter by State',
                                                border: OutlineInputBorder(),
                                              ),
                                              items: stateOptions
                                                  .map(
                                                    (state) => DropdownMenuItem<String>(
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
                                    ],
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
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
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
                                final showName = (s['name'] ?? '').toString();
                                final location = (s['location_name'] ?? '').toString();

                                final formattedStartDate =
                                    formatLocalDateTime(s['start_date']?.toString());

                                final entryDeadlineText =
                                    formatLocalDateTime(s['entry_close_at']?.toString());

                                final deadlinePassed = s['entry_close_at'] != null &&
                                    DateTime.parse(s['entry_close_at'].toString())
                                        .toLocal()
                                        .isBefore(DateTime.now());

                                final isAdminForShow = !widget.demoMode &&
                                    (bundle.isSuperAdmin ||
                                        bundle.adminShowIds.contains(showId));

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                                  child: RMCard(
                                    onTap: () => _openEnterShow(context, showId, showName),
                                    child: LayoutBuilder(
                                      builder: (context, cardConstraints) {
                                        final compactCard = cardConstraints.maxWidth < 640;

                                        final showInfo = Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              showName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(fontWeight: FontWeight.w700),
                                            ),
                                            const SizedBox(height: AppSpacing.sm),
                                            Text('$formattedStartDate • $location'),
                                            if (entryDeadlineText.isNotEmpty) ...[
                                              const SizedBox(height: AppSpacing.xs),
                                              Text(
                                                deadlinePassed
                                                    ? 'Entries closed: $entryDeadlineText'
                                                    : 'Entries close: $entryDeadlineText',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      color: deadlinePassed ? AppColors.danger : AppColors.muted,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                            ],
                                          ],
                                        );

                                        final actions = Wrap(
                                          spacing: AppSpacing.sm,
                                          runSpacing: AppSpacing.sm,
                                          alignment: compactCard ? WrapAlignment.start : WrapAlignment.end,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: () => _openBreedCounts(context, showId, showName),
                                              icon: const Icon(Icons.bar_chart, size: 18),
                                              label: const Text('Breed Counts'),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: () => _showPaymentInfo(context, showId, showName),
                                              icon: const Icon(Icons.payments_outlined, size: 18),
                                              label: const Text('Payment'),
                                            ),
                                            if (isAdminForShow)
                                              OutlinedButton.icon(
                                                onPressed: () => _openEditShow(context, showId),
                                                icon: const Icon(Icons.settings, size: 18),
                                                label: const Text('Manage'),
                                              ),
                                            FilledButton.icon(
                                              onPressed: () => _openEnterShow(context, showId, showName),
                                              icon: const Icon(Icons.login, size: 18),
                                              label: const Text('Enter Show'),
                                            ),
                                          ],
                                        );

                                        if (compactCard) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              showInfo,
                                              const SizedBox(height: AppSpacing.md),
                                              actions,
                                            ],
                                          );
                                        }

                                        return Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(child: showInfo),
                                            const SizedBox(width: AppSpacing.lg),
                                            actions,
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }
              }

              final impersonatedUser = _impersonatedUser;
              final demoResetText = widget.demoMode
                  ? _formatDemoResetText(bundle?.shows ?? const [])
                  : null;

              final demoBanner = widget.demoMode
                  ? Container(
                      width: double.infinity,
                      color: Colors.blue.shade50,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.science_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Demo Mode — this is a shared demo account. No login required. Entries are temporary and reset every 24 hours. Emails and real payments are disabled.${demoResetText == null ? '' : ' Resets in: $demoResetText'}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    )
                  : null;

              return Column(
                children: [
                  if (demoBanner != null) demoBanner,
                  if (impersonatedUser != null)
                    Container(
                      width: double.infinity,
                      color: Colors.amber.shade100,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.support_agent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Support Mode — ${impersonatedUser.label} (${impersonatedUser.email})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _exitSupportMode,
                            icon: const Icon(Icons.close),
                            label: const Text('Exit'),
                          ),
                        ],
                      ),
                    ),
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
  final bool showSuperintendent;
  final VoidCallback? onSuperintendent;
  final VoidCallback onAnimals;
  final VoidCallback onEntries;
  final VoidCallback onSuperAdmin;
  final VoidCallback onAccount;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final bool demoMode;

  const _ResponsiveShowAppBar({
    required this.bundle,
    required this.showAdmin,
    required this.onAdmin,
    required this.showSuperintendent,
    required this.onSuperintendent,
    required this.onAnimals,
    required this.onEntries,
    required this.onSuperAdmin,
    required this.onAccount,
    required this.onHelp,
    required this.onLogout,
    this.demoMode = false,
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
                      demoMode ? 'Demo Mode — RingMaster Show' : 'Upcoming Shows',
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
        if (!demoMode && showAdmin && onAdmin != null)
          _TopBarAction(
            icon: Icons.admin_panel_settings,
            label: 'Show Secretary',
            showLabel: showLabels,
            onTap: onAdmin!,
          ),
        if (!demoMode && showSuperintendent && onSuperintendent != null)
          _TopBarAction(
            icon: Icons.fact_check,
            label: 'Superintendent',
            showLabel: showLabels,
            onTap: onSuperintendent!,
          ),
        if (!demoMode)
          _TopBarAction(
            icon: Icons.pets,
            label: 'Animals',
            showLabel: showLabels,
            onTap: onAnimals,
          ),
        if (!demoMode)
          _TopBarAction(
            icon: Icons.receipt_long,
            label: 'Entries',
            showLabel: showLabels,
            onTap: onEntries,
          ),
        if (showSuperAdminInline)
          FutureBuilder<bool>(
            future: Future.value(
              !SupportImpersonationSession.isActive &&
                  (bundle?.isSuperAdmin ?? false),
            ),
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
        if (!demoMode)
          _TopBarAction(
            icon: Icons.manage_accounts,
            label: 'Account',
            showLabel: showLabels || medium,
            onTap: onAccount,
          ),
        _TopBarAction(
          icon: Icons.help_outline,
          label: 'Help',
          showLabel: showLabels || medium,
          onTap: onHelp,
        ),
        if (!demoMode)
          MyHelpRequestsButton(
            showLabel: showLabels || medium,
            iconColor: Colors.white,
            textColor: Colors.white,
          ),
        if (!showLabels)
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'superintendent' && onSuperintendent != null) {
                onSuperintendent!();
              }
              if (value == 'super_admin') onSuperAdmin();
              if (value == 'help') onHelp();
              if (value == 'logout') onLogout();
            },
            itemBuilder: (context) => [
              if (!demoMode && showSuperintendent && onSuperintendent != null)
                const PopupMenuItem<String>(
                  value: 'superintendent',
                  child: Text('Superintendent'),
                ),
              if (!demoMode &&
                  !SupportImpersonationSession.isActive &&
                  bundle?.isSuperAdmin == true)
                const PopupMenuItem<String>(
                  value: 'super_admin',
                  child: Text('Super Admin'),
                ),
              const PopupMenuItem<String>(
                value: 'help',
                child: Text('Help'),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Text('Logout'),
              ),
            ],
          )
        else ...[
          FutureBuilder<bool>(
            future: Future.value(
              !SupportImpersonationSession.isActive &&
                  (bundle?.isSuperAdmin ?? false),
            ),
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
                      ? 'Published shows will appear here once they are available. If you are a show secretary, open Show Secretary to create or manage shows.'
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
                        label: const Text('Open Show Secretary'),
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
