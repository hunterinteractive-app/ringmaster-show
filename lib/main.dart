// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';
import 'screens/show_list_screen.dart';
import 'screens/account_profile_setup_screen.dart';
import 'config/supabase_config.dart';




Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnon = String.fromEnvironment('SUPABASE_ANON_KEY');


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
      theme: ThemeData(useMaterial3: true),
      home: const Root(),
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
    _authSub = supabase.auth.onAuthStateChange.listen((_) {
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

    // Signed in: check if at least 1 exhibitor exists for this owner_user_id
    if (!mounted) return;
    setState(() {
      _loading = true;
      _msg = null;
    });

    try {
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
        _msg = 'Exhibitor check failed: $e';
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