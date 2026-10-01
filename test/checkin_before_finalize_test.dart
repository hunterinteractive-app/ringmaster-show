import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_closeout_v2_preview.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'closeout_v2_report_selection_show-1': jsonEncode({
        'group': 'exhibitor',
        'report_name': 'checkin_sheet',
        'exhibitor_id': 'late-exhibitor',
      }),
    });
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object body = [];
        if (path.endsWith('/entries')) {
          // Simulate server-capped pages: the late exhibitor must still appear.
          final offset = request.url.queryParameters['offset'] ?? '0';
          body = offset == '0'
              ? [
                  {
                    'exhibitor_id': 'first',
                    'exhibitors': {
                      'id': 'first',
                      'display_name': 'First Exhibitor',
                      'email': 'first@example.com',
                    },
                  },
                ]
              : offset == '1'
              ? [
                  {
                    'exhibitor_id': 'late-exhibitor',
                    'exhibitors': {
                      'id': 'late-exhibitor',
                      'display_name': 'Late Exhibitor',
                      'email': 'late@example.com',
                    },
                  },
                ]
              : [];
        } else if (path.endsWith('/shows')) {
          body = {
            'created_by': 'owner',
            'is_locked': false,
            'finalized_at': null,
          };
        } else if (path.contains('/rpc/')) {
          body = false;
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
  testWidgets(
    'unfinalized show without artifacts can generate an individual check-in sheet',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: ShowCloseoutV2PreviewPage(
            showId: 'show-1',
            showName: 'Unfinalized Show',
            canFinalizeShow: true,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(
        find.byKey(const PageStorageKey<String>('closeout-v2-show-1')),
        const Offset(0, -4000),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Late Exhibitor'), findsOneWidget);
      final generate = find.ancestor(
        of: find.text('Generate Selected Report'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      expect(generate, findsOneWidget);
      expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);
      final email = find.ancestor(
        of: find.text('Email Check-In Sheet'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(email, findsOneWidget);
      expect(tester.widget<OutlinedButton>(email).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
