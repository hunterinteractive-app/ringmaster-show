// lib/screens/login_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import '../widgets/rm_widgets.dart';
import 'show_list_screen.dart';

final supabase = Supabase.instance.client;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _msg;
  bool _busy = false;
  bool _showLogin = false;

  late Future<List<Map<String, dynamic>>> _publicShowsFuture;

  StreamSubscription<AuthState>? _sub;

  late final AnimationController _animationController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();

    _publicShowsFuture = _loadPublicShows();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoScale = Tween<double>(
      begin: 0.88,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _logoFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _cardFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _showLogin = true);
    });

    _sub = supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ShowListScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _email.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadPublicShows() async {
    final today = DateTime.now().toUtc().toIso8601String();

    final res = await supabase
        .from('shows')
        .select('id,name,start_date,location_name,entry_close_at')
        .eq('is_published', true)
        .gte('start_date', today)
        .order('start_date')
        // Change how many can be seen.
        .limit(50);

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> _sendLink() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: _email.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _msg = 'Check your email for the login link.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Error: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Email is required.';
    if (!text.contains('@') || !text.contains('.')) {
      return 'Enter a valid email.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.navyDark,
              AppColors.navy,
              Color(0xFF1B3D82),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.10),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),
                              child: _LogoBlock(),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            const Text(
                              'RingMaster Show',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Modern show management for rabbit, cavy, and small livestock events.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    FadeTransition(
                      opacity: _cardFade,
                      child: SlideTransition(
                        position: _cardSlide,
                        child: _PublicShowsCard(
                          showsFuture: _publicShowsFuture,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_showLogin)
                      FadeTransition(
                        opacity: _cardFade,
                        child: SlideTransition(
                          position: _cardSlide,
                          child: RMCard(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Sign in to Continue',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Sign in is required to enter a show, manage entries, or access exhibitor and admin tools.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  TextFormField(
                                    controller: _email,
                                    validator: _validateEmail,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) {
                                      if (!_busy) _sendLink();
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'Email address',
                                      hintText: 'you@example.com',
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _sendLink,
                                    icon: _busy
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.login),
                                    label: Text(
                                      _busy
                                          ? 'Sending link…'
                                          : 'Send magic link',
                                    ),
                                  ),
                                  if (_msg != null) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    Container(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: _msg!.startsWith('Error:')
                                            ? AppColors.dangerBg
                                            : AppColors.successBg,
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: Text(
                                        _msg!,
                                        style: TextStyle(
                                          color: _msg!.startsWith('Error:')
                                              ? AppColors.danger
                                              : AppColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.lg),
                                  Text(
                                    'Use the login link from your email to continue to RingMaster Show.',
                                    textAlign: TextAlign.center,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicShowsCard extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> showsFuture;

  const _PublicShowsCard({
    required this.showsFuture,
  });

  @override
  State<_PublicShowsCard> createState() => _PublicShowsCardState();
}

class _PublicShowsCardState extends State<_PublicShowsCard> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _sortMode = 'date';
  String _stateFilter = 'All';

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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _extractState(String location) {
    final raw = location.trim();
    if (raw.isEmpty) return '';

    final upper = raw.toUpperCase();

    final abbrPattern = RegExp(
      r'(?:^|,|\s)([A-Z]{2})(?=\s+\d{5}(?:-\d{4})?$|$)',
    );

    for (final match in abbrPattern.allMatches(upper)) {
      final abbr = match.group(1);
      if (abbr != null && _stateAbbreviationToName.containsKey(abbr)) {
        return _stateAbbreviationToName[abbr]!;
      }
    }

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

  @override
  Widget build(BuildContext context) {
    return RMCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Available Shows',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Browse published shows below. Sign in when you are ready to enter a show or manage your entries.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: widget.showsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snap.hasError) {
                return Text(
                  'Unable to load available shows right now.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                );
              }

              final allShows = snap.data ?? [];
              final stateOptions = _availableStates(allShows);
              final shows = _applyFiltersAndSort(allShows);

              if (allShows.isEmpty) {
                return Text(
                  'No published upcoming shows are available yet.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search shows',
                      hintText: 'Search by show name, location, state, or date',
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
                        width: 220,
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
                        width: 220,
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
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${shows.length} show${shows.length == 1 ? '' : 's'} found',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (shows.isEmpty)
                    Text(
                      'No shows match your current search or filters.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                    )
                  else
                    Column(
                      children: shows.map((show) {
                        final name = (show['name'] ?? '').toString();
                        final location =
                            (show['location_name'] ?? '').toString();
                        final date = formatLocalDateTime(
                          show['start_date']?.toString(),
                        );

                        final deadlineText = formatLocalDateTime(
                          show['entry_close_at']?.toString(),
                        );

                        final entryCloseRaw =
                            show['entry_close_at']?.toString();

                        final deadlinePassed = entryCloseRaw != null &&
                            entryCloseRaw.trim().isNotEmpty &&
                            DateTime.parse(entryCloseRaw)
                                .toLocal()
                                .isBefore(DateTime.now());

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: Colors.grey.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.event_available, size: 22),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name.isEmpty ? 'Untitled Show' : name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (date.trim().isNotEmpty) date,
                                        if (location.trim().isNotEmpty)
                                          location,
                                      ].join(' • '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppColors.muted),
                                    ),
                                    if (deadlineText.trim().isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.sm),
                                      RMBadge(
                                        text: deadlinePassed
                                            ? 'Entry Closed'
                                            : 'Entry Deadline: $deadlineText',
                                        icon: Icons.event_available,
                                        danger: deadlinePassed,
                                        success: !deadlinePassed,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LogoBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/ringmaster_show_logo.png',
          height: 160,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.emoji_events_outlined,
                size: 42,
                color: Colors.white,
              ),
            );
          },
        ),
      ],
    );
  }
}