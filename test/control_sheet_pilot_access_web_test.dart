@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ringmaster_show/screens/admin/print_packs/control_sheets_generator_sheet.dart';
import 'package:ringmaster_show/screens/admin/results/admin_results_entry_screen.dart';
import 'package:ringmaster_show/services/role_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const showId = '00000000-0000-0000-0000-000000000001';
  const sectionId = '00000000-0000-0000-0000-000000000002';
  testWidgets('only super admins see the pilot controls', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var role = 'admin';
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://bubble-pilot-fixture.invalid',
        anonKey: 'test',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
        httpClient: MockClient((request) async {
          final path = request.url.path;
          final Object data = switch (path.split('/').last) {
            'super_admins' => [],
            'role_assignments' =>
              role == 'super_admin'
                  ? [
                      {'role': role},
                    ]
                  : [],
            'shows' => {'is_locked': true, 'is_national_show': false},
            _ => [],
          };
          return http.Response(
            jsonEncode(data),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      String encode(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      final expires =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final token =
          '${encode({'alg': 'HS256'})}.${encode({'exp': expires, 'role': 'authenticated'})}.fixture';
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode({
          'access_token': token,
          'expires_in': 3600,
          'token_type': 'bearer',
          'user': {
            'id': '00000000-0000-0000-0000-000000000003',
            'aud': 'authenticated',
            'app_metadata': <String, Object>{},
            'user_metadata': <String, Object>{},
            'created_at': '2026-11-15T00:00:00Z',
          },
        }),
      );
    });
    addTearDown(() async => Supabase.instance.dispose());
    for (final superAdmin in [false, true]) {
      role = superAdmin ? 'super_admin' : 'admin';
      expect(await tester.runAsync(RoleService.isSuperAdmin), superAdmin);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ControlSheetsGeneratorSheet(
              showId: showId,
              showName: 'Pilot fixture',
              sections: const [],
              sectionId: sectionId,
              sectionIds: [sectionId],
              sectionLabel: 'Open A',
              includeScratched: false,
              combineSections: false,
              youthFirst: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Generate bubble control sheets (pilot)'),
        superAdmin ? findsOneWidget : findsNothing,
      );
      expect(find.text('Generate PDF'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: AdminResultsEntryScreen(
            showId: showId,
            showName: 'Pilot fixture',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Scan control sheets (pilot)'),
        superAdmin ? findsOneWidget : findsNothing,
      );
      if (superAdmin) {
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Scan control sheets (pilot)',
                ),
              )
              .onPressed,
          isNotNull,
          reason: 'The dry run is also available for locked shows.',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });
}
