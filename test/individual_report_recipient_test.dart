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
        'report_name': 'exhibitor_report',
        'exhibitor_id': 'late-exhibitor',
      }),
    });
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
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
        } else if (path.endsWith('/show_report_artifacts')) {
          body = [
            {
              'id': 'artifact-1',
              'show_id': 'show-1',
              'report_name': 'exhibitor_report',
              'artifact_status': 'generated',
              'is_current': true,
              'storage_bucket': 'reports',
              'storage_path': 'test.pdf',
              'metadata': {
                'exhibitor_id': 'late-exhibitor',
                'exhibitor_name': 'Late Exhibitor',
              },
            },
          ];
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
    'individual report resolves missing email from paginated exhibitor contacts',
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
      await tester.tap(find.text('Email Exhibitor Reports').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('to late@example.com.'), findsOneWidget);
      expect(
        find.text('No email recipient is configured for this report.'),
        findsNothing,
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
