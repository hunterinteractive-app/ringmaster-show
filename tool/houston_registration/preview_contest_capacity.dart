import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/models/contest_settings.dart';
import 'package:ringmaster_show/models/show_addon.dart';
import 'package:ringmaster_show/screens/admin/show_addon_settings_screen.dart';
import 'package:ringmaster_show/services/show_addon_service.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

// Uses the real setup screen with local-only responses. No live data is changed.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'http://preview.invalid',
    anonKey: 'preview',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
    httpClient: MockClient(
      (request) async => http.Response(
        'null',
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    ),
  );
  runApp(
    MaterialApp(
      theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
      home: ShowAddonEditorScreen(
        showId: 'preview',
        currency: 'usd',
        service: ShowAddonService(),
        item: ShowAddon(
          kind: 'contest',
          name: 'Rabbit/Cavy Costume Contest',
          priceCents: 500,
          contestSettings: ContestSettings({
            'categories': [
              'Best Rodeo Theme',
              'Most Elaborate Costume',
              'Funniest Costume',
              'Best Character Impersonation',
              'Most Colorful Costume',
            ],
            'category_session_capacity': 20,
            'sessions': [
              {
                'id': 'sat',
                'name': 'Saturday, March 6',
                'starts_at': '2027-03-06T20:30:00Z',
                'ends_at': '2027-03-06T23:30:00Z',
                'capacity': 100,
              },
              {
                'id': 'mon',
                'name': 'Monday, March 8',
                'starts_at': '2027-03-08T21:30:00Z',
                'ends_at': '2027-03-09T00:30:00Z',
                'capacity': 100,
              },
            ],
          }),
        ),
      ),
    ),
  );
}
