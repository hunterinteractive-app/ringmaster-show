// lib/main.dart 
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:ringmaster_show/services/help_report_service.dart';

import 'package:ringmaster_show/screens/admin/judging/mobile/qr_results_entry_screen.dart';
import 'package:ringmaster_show/screens/admin/judging/mobile/table_qr_queue_screen.dart';

import 'screens/login_screen.dart';
import 'screens/show_list_screen.dart';
import 'screens/account_profile_setup_screen.dart';

import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'services/app_init_service.dart';

final supabase = Supabase.instance.client;

Uri? initialQrUri;
bool initialDemoMode = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseConfig.validate();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  initialQrUri = _qrUriFromBrowser();
  initialDemoMode = _demoModeFromBrowser();

  runApp(const MyApp());
}

Uri? _qrUriFromBrowser() {
  final fragment = Uri.base.fragment.trim();

  if (fragment.isNotEmpty) {
    final uri = Uri.parse(fragment);
    if (uri.path == '/qr-results-entry' || uri.path == '/qr-table-results') {
      return uri;
    }
  }

  final path = Uri.base.path.trim();
  if (path.endsWith('/qr-results-entry') || path.endsWith('/qr-table-results')) {
    return Uri.base;
  }

  return null;
}

bool _demoModeFromBrowser() {
  final fragment = Uri.base.fragment.trim();

  if (fragment.isNotEmpty) {
    final uri = Uri.parse(fragment);
    if (uri.path == '/demo') return true;
  }

  final path = Uri.base.path.trim();
  return path.endsWith('/demo');
}

Widget _qrScreenFromUri(Uri uri) {
  return QrResultsEntryScreen(
    showId: uri.queryParameters['showId'] ?? '',
    sectionId: uri.queryParameters['sectionId'] ?? '',
    breedId: uri.queryParameters['breedId'] ??
        uri.queryParameters['breed'] ??
        '',
    token: uri.queryParameters['token'] ?? '',
    varietyKey: uri.queryParameters['varietyKey'],
    groupKey: uri.queryParameters['groupKey'],
    classSexLabel: uri.queryParameters['classSexLabel'],
  );
}

Widget _tableQrScreenFromUri(Uri uri) {
  return TableQrQueueScreen(
    showId: uri.queryParameters['showId'] ?? '',
    tableNumber: uri.queryParameters['table'] ??
        uri.queryParameters['tableNumber'] ??
        '',
    token: uri.queryParameters['token'] ?? '',
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Screenshot(
      controller: HelpReportService.screenshotController,
      child: MaterialApp(
        title: 'RingMaster Show',
        theme: AppTheme.lightTheme,
        home: const Root(),
        onGenerateRoute: (settings) {
          final routeUri = Uri.parse(settings.name ?? '');
          Uri uri = routeUri;

          if (Uri.base.fragment.isNotEmpty) {
            uri = Uri.parse(Uri.base.fragment);
          }

          if (uri.path == '/qr-table-results') {
            return MaterialPageRoute(
              builder: (_) => _tableQrScreenFromUri(uri),
            );
          }

          if (uri.path == '/qr-results-entry') {
            return MaterialPageRoute(
              builder: (_) => _qrScreenFromUri(uri),
            );
          }

          if (uri.path == '/demo') {
            return MaterialPageRoute(
              builder: (_) => const DemoLoginScreen(),
            );
          }

          return null;
        },
      ),
    );
  }
}

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

    initialQrUri ??= _qrUriFromBrowser();
    initialDemoMode = initialDemoMode || _demoModeFromBrowser();

    _refresh();

    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      initialQrUri ??= _qrUriFromBrowser();
      initialDemoMode = initialDemoMode || _demoModeFromBrowser();

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
    final demoMode = initialDemoMode || _demoModeFromBrowser();

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasExhibitor = false;
        _msg = null;
      });
      return;
    }

    if (demoMode) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasExhibitor = true;
        _msg = null;
      });
      return;
    }

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
    final qrUri = initialQrUri ?? _qrUriFromBrowser();
    final session = supabase.auth.currentSession;
    final demoMode = initialDemoMode || _demoModeFromBrowser();

    if (qrUri != null) {
      if (qrUri.path == '/qr-table-results') {
        return _tableQrScreenFromUri(qrUri);
      }
      return _qrScreenFromUri(qrUri);
    }

    if (demoMode) {
      return const DemoLoginScreen();
    }

    if (session == null) return const LoginScreen();

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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

    // if (demoMode) return const ShowListScreen(demoMode: true);

    if (!_hasExhibitor) return const AccountProfileSetupScreen();

    return const ShowListScreen();
  }
}