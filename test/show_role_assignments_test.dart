import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_role_assignments_dialog.dart';

void main() {
  Map<String, dynamic>? saved;
  final roles = [
    {'id': 'owner-role', 'user_id': 'owner', 'role': 'admin'},
    {
      'id': 'secretary-role',
      'user_id': 'shared',
      'role': 'admin',
      'staff_name': 'Bonnie Saunier',
    },
    {
      'id': 'super-role',
      'user_id': 'shared',
      'role': 'superintendent',
      'staff_name': 'Eric Saunier',
    },
  ];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        Object? body;
        if (request.url.path.endsWith('/shows')) {
          body = {'owner_user_id': 'owner'};
        } else if (request.url.path.endsWith('/role_assignments')) {
          if (request.url.queryParameters.containsKey('user_id')) {
            expect(request.url.queryParameters['role'], 'eq.superintendent');
            body = [roles[2]];
          } else {
            body = roles;
          }
        } else if (request.url.path.endsWith('/search_show_staff_users')) {
          final params = jsonDecode(request.body) as Map;
          body = params['p_query'] != null
              ? [
                  {
                    'id': 'shared',
                    'email': 'shared@example.com',
                    'display_name': 'Eric Saunier',
                    'exhibitor_id': 'eric',
                  },
                ]
              : [
                  {
                    'id': 'owner',
                    'email': 'club@example.com',
                    'display_name': '',
                  },
                  // Account fallback must not replace either saved person's name.
                  {
                    'id': 'shared',
                    'email': 'shared@example.com',
                    'display_name': 'Account Default',
                  },
                ];
        } else if (request.url.path.endsWith('/assign_show_staff_person')) {
          saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
          body = 'super-role';
        } else {
          throw StateError('Unexpected request: ${request.url}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'shared-account roles keep their people through saving and reopening',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ShowRoleAssignmentsDialog.open(
                  context,
                  showId: 'show',
                  showName: 'Test Show',
                ),
                child: const Text('Open roles'),
              ),
            ),
          ),
        ),
      );
      Future<void> open() async {
        await tester.tap(find.text('Open roles'));
        await tester.pumpAndSettle();
      }

      void verifyPeople() {
        expect(
          find.text('Bonnie Saunier • shared@example.com'),
          findsOneWidget,
        );
        expect(find.text('Eric Saunier • shared@example.com'), findsOneWidget);
        expect(find.text('Account Owner / Administrator'), findsOneWidget);
        expect(find.textContaining('Account Default'), findsNothing);
      }

      await open();
      verifyPeople();
      await tester.enterText(find.byType(TextField), 'Eric');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Eric Saunier'));
      await tester.tap(find.text('Eric Saunier'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add / Update Role'));
      await tester.tap(find.text('Add / Update Role'));
      await tester.pumpAndSettle();
      expect(saved, {
        'p_show_id': 'show',
        'p_user_id': 'shared',
        'p_role': 'superintendent',
        'p_exhibitor_id': 'eric',
      });
      verifyPeople();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await open();
      verifyPeople();
      expect(tester.takeException(), isNull);
    },
  );
}
