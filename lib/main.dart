// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/judging/mobile/qr_results_entry_screen.dart';

import 'screens/login_screen.dart';
import 'screens/show_list_screen.dart';
import 'screens/account_profile_setup_screen.dart';

import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'services/app_init_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseConfig.validate();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RingMaster Show',
      theme: AppTheme.lightTheme,
      home: const Root(),
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        if (uri.path == '/qr-results-entry') {
          return MaterialPageRoute(
            builder: (_) => QrResultsEntryScreen(
              showId: uri.queryParameters['showId'] ?? '',
              sectionId: uri.queryParameters['sectionId'] ?? '',
              breedId: uri.queryParameters['breedId'] ?? '',
              token: uri.queryParameters['token'] ?? '',

              // Leave these optional.
              // Normal QR codes should NOT include these.
              varietyKey: uri.queryParameters['varietyKey'],
              groupKey: uri.queryParameters['groupKey'],
              classSexLabel: uri.queryParameters['classSexLabel'],
            ),
          );
        }

        return null;
      },
    );
  }
}

/// Decides where to send the user:
/// - not signed in -> LoginScreen
/// - signed in but no exhibitor yet -> AccountProfileSetupScreen
/// - signed in and has at least 1 exhibitor -> ShowListScreen
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _loading = true;
  bool _hasExhibitor = false;
  String? _msg;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _refresh();

    // React to sign-in/sign-out immediately
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedOut || session == null) {
        AppInitService.reset();
      }

      _refresh();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final user = supabase.auth.currentUser;

    // Not signed in
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasExhibitor = false;
        _msg = null;
      });
      return;
    }

    // Signed in: claim pending licenses first, then check exhibitor
    if (!mounted) return;
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
      await AppInitService.initializeForCurrentUser();

      final row = await supabase
          .from('exhibitors')
          .select('id')
          .eq('owner_user_id', user.id)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _hasExhibitor = row != null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasExhibitor = false;
        _msg = 'Startup check failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;

    // Logged out
    if (session == null) return const LoginScreen();

    // Logged in: show spinner while checking exhibitor
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Error checking
    if (_msg != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_msg!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _refresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // No exhibitor yet -> force setup
    if (!_hasExhibitor) return const AccountProfileSetupScreen();

    // Has exhibitor -> proceed
    return const ShowListScreen();
  }
}