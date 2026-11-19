// Requires flutter test --platform chrome.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ringmaster_show/config/legal_config.dart';
import 'package:ringmaster_show/config/show_layout_rollout.dart';
import 'package:ringmaster_show/screens/account_settings_screen.dart';
import 'package:ringmaster_show/screens/admin/edit_show_settings_screen.dart';
import 'package:ringmaster_show/screens/cart_screen.dart';
import 'package:ringmaster_show/screens/show_list_screen.dart';
import 'package:ringmaster_show/services/support_impersonation_session.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/show_layout_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const superAdmin = 'aaaaaaaa-0000-4000-8000-000000000001';
const secretary = 'aaaaaaaa-0000-4000-8000-000000000002';
const showId = 'bbbbbbbb-0000-4000-8000-000000000001';
const cartId = 'cccccccc-0000-4000-8000-000000000001';
const exhibitorId = 'dddddddd-0000-4000-8000-000000000001';
const showName = 'Meadowbrook Spring Rabbit Show';

Future<void> _signIn(String actor) async {
  final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final session = {
    'access_token':
        '${segment({'alg': 'HS256'})}.${segment({'sub': actor, 'exp': expires, 'role': 'authenticated'})}.fixture',
    'refresh_token': 'fixture',
    'token_type': 'bearer',
    'expires_at': expires,
    'expires_in': 3600,
    'user': {
      'id': actor,
      'aud': 'authenticated',
      'email': 'fixture@example.invalid',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {},
    },
  };
  await Supabase.instance.client.auth.recoverSession(jsonEncode(session));
}

Future<void> _open(
  WidgetTester tester,
  Widget screen, {
  ShowLayoutRollout phase = ShowLayoutRollout.superAdminPreview,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (_, child) => ShowLayoutHost(rollout: phase, child: child!),
      home: screen,
    ),
  );
  await _render(tester);
}

Future<void> _render(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Drain the existing timezone notice timer after disposing the screen.
  await tester.pump(const Duration(minutes: 5));
}

void main() {
  late Map<String, dynamic> show;
  final requests = <Uri>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    show = {
      'id': showId,
      'name': showName,
      'location_name': 'Lebanon, IN',
      'start_date': now.toIso8601String().substring(0, 10),
      'is_published': true,
      'entry_open_at': now.subtract(const Duration(days: 4)).toIso8601String(),
      'entry_close_at': now.add(const Duration(days: 1)).toIso8601String(),
      'timezone': 'America/Indiana/Indianapolis',
      'is_locked': false,
    };
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        final path = request.url.path.split('/').last;
        final query = request.url.queryParameters;
        final administrator = query['user_id'] == 'eq.$superAdmin';
        Object? data = switch (path) {
          'super_admins' =>
            administrator
                ? [
                    {'user_id': superAdmin},
                  ]
                : [],
          'role_assignments' =>
            administrator
                ? [
                    {'role': 'super_admin', 'show_id': showId},
                  ]
                : [],
          'show_admins' => [
            {'show_id': showId},
          ],
          'shows' =>
            request.headers['Accept'] == 'application/vnd.pgrst.object+json'
                ? show
                : [show],
          'profiles' => [
            {
              'primary_exhibitor_id': exhibitorId,
              'accepted_terms_version': LegalConfig.currentTermsVersion,
              'accepted_privacy_version': LegalConfig.currentPrivacyVersion,
            },
          ],
          'household_access' => {'households': [], 'invitations': []},
          'claim-or-import-exhibitor' => {'status': 'already_exists'},
          'exhibitors' => [
            {
              'id': exhibitorId,
              'display_name': 'Sample Exhibitor',
              'type': 'adult',
              'is_active': true,
            },
          ],
          'show_checkin_settings' => [
            {'is_enabled': true},
          ],
          'get_show_checkin_dashboard' => {
            'pending_change_requests': 3,
            'unpaid_exhibitors': 2,
            'records': {'completed': 6, 'reviewed': 1},
          },
          'get_show_checkout_options' => {
            'payment_timing_mode': 'pay_at_show_only',
            'allow_at_show': true,
          },
          'user_can_manage_show' || 'user_can_manage_entries' => true,
          'entry_carts' when query['status'] == 'eq.active' => [
            {
              'id': cartId,
              'show_id': showId,
              'shows': show,
              'entry_cart_items': [
                {'id': 'item'},
              ],
            },
          ],
          _ when path.startsWith('user_can_') => false,
          _ => [],
        };
        if ((request.headers['Accept'] ?? '').contains('pgrst.object') &&
            data is List &&
            data.length == 1) {
          data = data.single;
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets(
    'Super Admin can switch both layouts and resume a draft on mobile',
    (tester) async {
      await _signIn(superAdmin);
      await _open(tester, const ShowListScreen());
      expect(find.text('Upcoming Shows'), findsOneWidget);
      await tester.tap(find.byTooltip('More'));
      await _render(tester);
      await tester.tap(find.text('Account'));
      await _render(tester);
      final layoutSwitch = find.widgetWithText(
        SwitchListTile,
        'Use updated layout',
      );
      expect(tester.widget<SwitchListTile>(layoutSwitch).value, isFalse);
      await tester.tap(layoutSwitch);
      await _render(tester);
      expect(tester.widget<SwitchListTile>(layoutSwitch).value, isTrue);
      await tester.tap(layoutSwitch);
      await _render(tester);
      expect(tester.widget<SwitchListTile>(layoutSwitch).value, isFalse);
      await tester.tap(layoutSwitch);
      await _render(tester);
      expect(tester.widget<SwitchListTile>(layoutSwitch).value, isTrue);
      Navigator.of(tester.element(layoutSwitch)).pop();
      await _render(tester);

      expect(find.text('Open for Entry'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Search shows'), findsOneWidget);
      expect(find.text('Sort by'), findsNothing);
      await tester.tap(find.text('Filters'));
      await _render(tester);
      expect(find.text('Sort by'), findsOneWidget);
      await tester.tap(find.text('Filters'));
      await _render(tester);
      final showDetails = find.text('Show details');
      await tester.ensureVisible(showDetails);
      await tester.tap(showDetails);
      await _render(tester);
      await tester.tap(find.text('Payment options'));
      await _render(tester);
      expect(find.text('Pay at the show'), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      expect(
        Theme.of(tester.element(dialog)).dialogTheme.backgroundColor,
        AppColors.surface,
      );
      await tester.tap(find.text('Close'));
      await _render(tester);

      await tester.tap(find.text('My Entries'));
      await _render(tester);
      expect(find.text('Draft cart · Awaiting submission'), findsOneWidget);
      final request = requests.lastWhere(
        (uri) =>
            uri.queryParameters['select']?.contains('entry_cart_items!inner') ==
            true,
      );
      expect(request.queryParameters['user_id'], 'eq.$superAdmin');
      await tester.tap(find.text('Resume checkout'));
      await _render(tester);
      expect(tester.widget<CartScreen>(find.byType(CartScreen)).cartId, cartId);
      Navigator.of(tester.element(find.byType(CartScreen))).pop();
      await _render(tester);
      await tester.tap(find.text('Past Reports'));
      await _render(tester);
      expect(
        requests.any(
          (uri) => uri.path.endsWith('/household_exhibitor_past_show_reports'),
        ),
        isTrue,
      );
      expect(find.text('My Animals'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);

      await _open(tester, const EditShowSettingsScreen(showId: showId));
      expect(find.text('3 pending change requests'), findsOneWidget);
      expect(find.text('Review change requests'), findsOneWidget);
      await tester.tap(find.text('Judging'));
      await _render(tester);
      expect(find.text('Results Entry'), findsOneWidget);
      expect(find.text('Superintendent Lineup'), findsOneWidget);
      expect(find.text('Control Sheets'), findsOneWidget);
      expect(find.text('Basic Show Info'), findsNothing);
      await tester.tap(find.text('Finances'));
      await _render(tester);
      expect(find.text('Balances & Payment History'), findsOneWidget);
      expect(find.text('Fees & Payment Setup'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets('preview ignores a stored preference for an ordinary secretary', (
    tester,
  ) async {
    await _signIn(secretary);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('updated_show_layout.$secretary', true);
    await _open(tester, const AccountSettingsScreen());
    expect(find.text('Use updated layout'), findsNothing);
    await _close(tester);
    await _open(
      tester,
      const EditShowSettingsScreen(showId: showId),
      size: const Size(1200, 900),
    );
    expect(find.text('Basic Show Info'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
    await _close(tester);
  });

  testWidgets('public opt-in and launch keep the secretary permission gates', (
    tester,
  ) async {
    await _signIn(secretary);
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('updated_show_layout.$secretary');
    await _open(
      tester,
      const AccountSettingsScreen(),
      phase: ShowLayoutRollout.optIn,
    );
    final layoutSwitch = find.widgetWithText(
      SwitchListTile,
      'Use updated layout',
    );
    expect(tester.widget<SwitchListTile>(layoutSwitch).value, isFalse);
    await tester.tap(layoutSwitch);
    await _render(tester);
    expect(tester.widget<SwitchListTile>(layoutSwitch).value, isTrue);
    SupportImpersonationSession.start(
      const SupportImpersonatedUser(
        userId: superAdmin,
        email: 'support-target@example.invalid',
        displayName: 'Support Target',
        exhibitorName: '',
      ),
    );
    await _render(tester);
    expect(find.text('Use updated layout'), findsNothing);
    SupportImpersonationSession.stop();
    await _render(tester);
    expect(tester.widget<SwitchListTile>(layoutSwitch).value, isTrue);
    await _close(tester);

    await _open(
      tester,
      const EditShowSettingsScreen(showId: showId),
      phase: ShowLayoutRollout.optIn,
      size: const Size(1200, 900),
    );
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Reports & Closeout'), findsNothing);
    await tester.tap(find.text('Judging'));
    await _render(tester);
    expect(find.text('Control Sheets'), findsOneWidget);
    expect(find.text('Results Entry'), findsNothing);
    expect(tester.takeException(), isNull);
    await _close(tester);

    await preferences.remove('updated_show_layout.$secretary');
    await _open(
      tester,
      const AccountSettingsScreen(),
      phase: ShowLayoutRollout.launched,
    );
    expect(find.text('Use updated layout'), findsNothing);
    final scope = ShowLayoutScope.of(
      tester.element(find.byType(AccountSettingsScreen)),
    )!;
    expect(scope.updated, isTrue);
    await _close(tester);
  });
}
