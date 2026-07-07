// lib/screens/login_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../utils/date_time_utils.dart';
import '../widgets/rm_widgets.dart';
import '../services/app_init_service.dart';
import 'show_list_screen.dart';
import 'admin/admin_shows_screen.dart';
import 'legal/terms_screen.dart';
import 'legal/privacy_policy_screen.dart';

//dev backdoor
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
//dev backdoor

final supabase = Supabase.instance.client;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  String? _msg;
  String? _pendingEmail;
  bool _busy = false;
  bool _showLogin = false;
  bool _handlingAuth = false;
  bool _awaitingCode = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  late Future<List<Map<String, dynamic>>> _publicShowsFuture;

  StreamSubscription<AuthState>? _sub;

  late final AnimationController _animationController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  //dev backdoor

  int _logoTapCount = 0;
  DateTime? _lastLogoTapAt;

  Future<void> _handleLogoTap() async {
    if (kReleaseMode || _busy) return;

    final now = DateTime.now();

    if (_lastLogoTapAt == null ||
        now.difference(_lastLogoTapAt!) > const Duration(seconds: 4)) {
      _logoTapCount = 0;
    }

    _lastLogoTapAt = now;
    _logoTapCount++;

    HapticFeedback.selectionClick();

    if (_logoTapCount >= 7) {
      _logoTapCount = 0;
      await _devLogin();
    }
  }

  Future<void> _devLogin() async {
    setState(() {
      _busy = true;
      _msg = 'Dev login triggered...';
    });

    try {
      await supabase.auth.signInWithPassword(
        email: 'test@ringmaster.dev',
        password: 'Smile!987',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _msg = 'Dev login failed: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  //dev backdoor

  @override
  void initState() {
    super.initState();

    _publicShowsFuture = _loadPublicShows();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );

    _cardSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAuthCallbackIfPresent();
    });

    final existingSession = supabase.auth.currentSession;
    if (existingSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _handlingAuth) return;
        _goToShowList();
      });
    }

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _showLogin = true);
    });

    _sub = supabase.auth.onAuthStateChange.listen((data) async {
      if (data.session == null || !mounted || _handlingAuth) return;
      _goToShowList();
    });
  }

  Future<void> _handleAuthCallbackIfPresent() async {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final tokenHash = uri.queryParameters['token_hash'];

    final hasCode = code != null && code.trim().isNotEmpty;
    final hasTokenHash = tokenHash != null && tokenHash.trim().isNotEmpty;

    if (!hasCode && !hasTokenHash) return;
    if (_handlingAuth) return;

    setState(() {
      _busy = true;
      _msg = 'Finishing login...';
    });

    try {
      if (hasTokenHash) {
        final typeParam = uri.queryParameters['type']?.trim();

        final otpType = switch (typeParam) {
          'signup' => OtpType.signup,
          'magiclink' => OtpType.magiclink,
          'recovery' => OtpType.recovery,
          'email_change' => OtpType.emailChange,
          _ => OtpType.email,
        };

        await supabase.auth.verifyOTP(
          tokenHash: tokenHash!.trim(),
          type: otpType,
        );
      } else {
        await supabase.auth.exchangeCodeForSession(code!.trim());
      }

      if (!mounted) return;
      _goToShowList();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _msg = 'Error finishing login: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  void _goToShowList() {
    if (!mounted || _handlingAuth) return;

    _handlingAuth = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ShowListScreen()),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _resendTimer?.cancel();
    _email.dispose();
    _otp.dispose();
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

  void _startResendCountdown() {
    _resendTimer?.cancel();

    setState(() {
      _resendSeconds = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() {
          _resendSeconds = 0;
        });
        return;
      }

      setState(() {
        _resendSeconds--;
      });
    });
  }

  Future<void> _sendCode({bool isResend = false}) async {
    FocusScope.of(context).unfocus();

    if (!isResend && !_formKey.currentState!.validate()) return;

    final email = isResend
        ? (_pendingEmail ?? '').trim().toLowerCase()
        : _email.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() {
        _msg = 'Error: Enter your email address first.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      await supabase.auth.signInWithOtp(email: email, shouldCreateUser: true);

      if (!mounted) return;

      _otp.clear();
      setState(() {
        _pendingEmail = email;
        _awaitingCode = true;
        _msg = isResend
            ? 'A new login code was sent to $email.'
            : 'Enter the 6-digit login code sent to $email.';
      });
      _startResendCountdown();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Error: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Error: Unable to send the login code. Please try again.';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();

    final email = (_pendingEmail ?? '').trim().toLowerCase();
    final code = _otp.text.replaceAll(RegExp(r'\D'), '');

    if (email.isEmpty) {
      setState(() {
        _msg = 'Error: Enter your email address and request a new code.';
        _awaitingCode = false;
      });
      return;
    }

    if (code.length != 6) {
      setState(() {
        _msg = 'Error: Enter the complete 6-digit login code.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _msg = 'Verifying your login code...';
    });

    try {
      final response = await supabase.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

      if (response.session == null) {
        throw const AuthException('The login code could not be verified.');
      }

      if (!mounted) return;
      _goToShowList();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = e.message.toLowerCase().contains('expired')
            ? 'Error: This code has expired. Request a new code and try again.'
            : 'Error: The code is invalid or has already been used.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Error: Unable to verify the login code. Please try again.';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    FocusScope.of(context).unfocus();
    _resendTimer?.cancel();
    _otp.clear();

    setState(() {
      _awaitingCode = false;
      _pendingEmail = null;
      _resendSeconds = 0;
      _msg = null;
    });
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
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: SafeArea(
          child: Center(
            child: Theme(
              data: Theme.of(context).copyWith(
                scrollbarTheme: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(
                    AppColors.headerForeground,
                  ),
                  trackColor: WidgetStateProperty.all(
                    AppColors.headerForeground.withValues(alpha: .18),
                  ),
                  thickness: WidgetStateProperty.all(8),
                  radius: const Radius.circular(8),
                ),
              ),
              child: Scrollbar(
                thumbVisibility: true,
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
                                //dev backdoor
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _handleLogoTap,
                                  child: const _LogoBlock(),
                                ),
                                //dev backdoor
                                const SizedBox(height: AppSpacing.lg),
                                const Text(
                                  'RingMaster Show',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.headerForeground,
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
                                    color: AppColors.headerForeground,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_showLogin)
                          FadeTransition(
                            opacity: _cardFade,
                            child: SlideTransition(
                              position: _cardSlide,
                              child: _LoginCard(
                                formKey: _formKey,
                                emailController: _email,
                                otpController: _otp,
                                pendingEmail: _pendingEmail,
                                awaitingCode: _awaitingCode,
                                resendSeconds: _resendSeconds,
                                busy: _busy,
                                message: _msg,
                                validateEmail: _validateEmail,
                                onSendCode: () => _sendCode(),
                                onVerifyCode: _verifyCode,
                                onResendCode: () => _sendCode(isResend: true),
                                onChangeEmail: _changeEmail,
                                onOtpChanged: (value) {
                                  if (value.length == 6 && !_busy) {
                                    _verifyCode();
                                  }
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        FadeTransition(
                          opacity: _cardFade,
                          child: SlideTransition(
                            position: _cardSlide,
                            child: _PublicShowsCard(
                              showsFuture: _publicShowsFuture,
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
        ),
      ),
    );
  }
}

class DemoLoginScreen extends StatefulWidget {
  const DemoLoginScreen({super.key});

  @override
  State<DemoLoginScreen> createState() => _DemoLoginScreenState();
}

class _DemoLoginScreenState extends State<DemoLoginScreen> {
  bool _busy = false;
  String? _msg;

  static const String _demoEmail = 'demo@ringmasterone.com';
  static const String _demoPassword = 'Demo!987';
  static const String _demoShowId = '0f432fe8-2be2-467a-842f-ff3777436992';

  Future<void> _enterDemo({required bool asSecretary}) async {
    setState(() {
      _busy = true;
      _msg = null;
    });

    try {
      await supabase.auth.signInWithPassword(
        email: _demoEmail,
        password: _demoPassword,
      );

      await AppInitService.initializeForCurrentUser();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => asSecretary
              ? const AdminShowsScreen(
                  allowedShowIds: [_demoShowId],
                  demoMode: true,
                )
              : const ShowListScreen(demoMode: true, demoSecretaryMode: false),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = 'Unable to enter demo: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.page),
        child: SafeArea(
          child: Center(
            child: Theme(
              data: Theme.of(context).copyWith(
                scrollbarTheme: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(
                    AppColors.headerForeground,
                  ),
                  trackColor: WidgetStateProperty.all(
                    AppColors.headerForeground.withValues(alpha: .18),
                  ),
                  thickness: WidgetStateProperty.all(8),
                  radius: const Radius.circular(8),
                ),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _LogoBlock(),
                        const SizedBox(height: AppSpacing.lg),
                        const Text(
                          'RingMaster Show Demo',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.headerForeground,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Try RingMaster Show as an exhibitor entering animals or as a show secretary managing the demo show.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.headerForeground,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        RMCard(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Enter the Demo',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              const Text(
                                'Choose how you want to explore the shared demo. It resets every 24 hours, and emails, real payments, and official report delivery are disabled.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              SizedBox(
                                height: 52,
                                child: FilledButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _enterDemo(asSecretary: false),
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.person_outline),
                                  label: Text(
                                    _busy
                                        ? 'Opening Demo…'
                                        : 'View as Exhibitor',
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              SizedBox(
                                height: 52,
                                child: OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _enterDemo(asSecretary: true),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  label: const Text('View as Show Secretary'),
                                ),
                              ),
                              if (_msg != null) ...[
                                const SizedBox(height: AppSpacing.lg),
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerBg,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    _msg!,
                                    style: const TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.lg),
                              Text(
                                'Use this link for hands-on testing only. Demo changes are temporary.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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

  const _PublicShowsCard({required this.showsFuture});

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

      final firstTokenMatch = RegExp(
        r'^([A-Z]{2})(?:\s|$)',
      ).firstMatch(partUpper);

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
    final values =
        shows
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
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
                          initialValue: _sortMode,
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
                          initialValue: stateOptions.contains(_stateFilter)
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
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (shows.isEmpty)
                    Text(
                      'No shows match your current search or filters.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    )
                  else
                    Column(
                      children: shows.map((show) {
                        final name = (show['name'] ?? '').toString();
                        final location = (show['location_name'] ?? '')
                            .toString();
                        final date = formatLocalDateTime(
                          show['start_date']?.toString(),
                        );

                        final deadlineText = formatLocalDateTime(
                          show['entry_close_at']?.toString(),
                        );

                        final entryCloseRaw = show['entry_close_at']
                            ?.toString();

                        final deadlinePassed =
                            entryCloseRaw != null &&
                            entryCloseRaw.trim().isNotEmpty &&
                            DateTime.parse(
                              entryCloseRaw,
                            ).toLocal().isBefore(DateTime.now());

                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: AppColors.headerForeground,
                              width: 1.4,
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
  const _LogoBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/RingMaster_One_Show_Transparent.png',
          height: 280,
          width: 480,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox(
              width: 240,
              height: 160,
              child: Icon(
                Icons.emoji_events_outlined,
                size: 52,
                color: Colors.white,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController otpController;
  final String? pendingEmail;
  final bool awaitingCode;
  final int resendSeconds;
  final bool busy;
  final String? message;
  final String? Function(String?) validateEmail;
  final VoidCallback onSendCode;
  final VoidCallback onVerifyCode;
  final VoidCallback onResendCode;
  final VoidCallback onChangeEmail;
  final ValueChanged<String> onOtpChanged;

  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.otpController,
    required this.pendingEmail,
    required this.awaitingCode,
    required this.resendSeconds,
    required this.busy,
    required this.message,
    required this.validateEmail,
    required this.onSendCode,
    required this.onVerifyCode,
    required this.onResendCode,
    required this.onChangeEmail,
    required this.onOtpChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RMCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              awaitingCode
                  ? 'Enter your login code'
                  : 'Log in or create your account',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              awaitingCode
                  ? 'We sent a secure 6-digit code to ${pendingEmail ?? emailController.text.trim()}.'
                  : 'Enter your email to receive a secure 6-digit code for show entries, exhibitor tools, and show access.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!awaitingCode) ...[
              TextFormField(
                controller: emailController,
                validator: validateEmail,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.email],
                onFieldSubmitted: (_) {
                  if (!busy) onSendCode();
                },
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: busy ? null : onSendCode,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.mark_email_read_outlined),
                  label: Text(busy ? 'Sending code…' : 'Send login code'),
                ),
              ),
            ] else ...[
              TextFormField(
                controller: otpController,
                enabled: !busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 10,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                autofillHints: const [AutofillHints.oneTimeCode],
                onChanged: onOtpChanged,
                onFieldSubmitted: (_) {
                  if (!busy) onVerifyCode();
                },
                decoration: const InputDecoration(
                  labelText: '6-digit login code',
                  hintText: '000000',
                  prefixIcon: Icon(Icons.password_outlined),
                  counterText: '',
                ),
                maxLength: 6,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: busy ? null : onVerifyCode,
                  icon: busy
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
                    busy ? 'Verifying code…' : 'Continue to RingMaster Show',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                children: [
                  TextButton(
                    onPressed: busy || resendSeconds > 0 ? null : onResendCode,
                    child: Text(
                      resendSeconds > 0
                          ? 'Resend code in ${resendSeconds}s'
                          : 'Resend code',
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : onChangeEmail,
                    child: const Text('Change email'),
                  ),
                ],
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: message!.startsWith('Error:')
                      ? AppColors.dangerBg
                      : AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  message!,
                  style: TextStyle(
                    color: message!.startsWith('Error:')
                        ? AppColors.danger
                        : AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              awaitingCode
                  ? 'Do not share your login code. RingMaster Show will never ask you to send it by email, text, or phone.'
                  : 'The code can only be used once and will expire after 20 minutes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'By continuing, you agree to the RingMaster Show Terms of Service and Privacy Policy.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TermsScreen()),
                    );
                  },
                  child: const Text('Terms of Service'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                  child: const Text('Privacy Policy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
