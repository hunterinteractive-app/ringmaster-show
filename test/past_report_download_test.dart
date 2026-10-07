import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Use the launcher's platform seam to avoid navigating the test browser.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:ringmaster_show/screens/exhibitor_past_reports_screen.dart';

class RecordingLauncher extends UrlLauncherPlatform {
  @override
  final linkDelegate = null;

  final calls = <({String url, LaunchOptions options})>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url: url, options: options));
    return true;
  }
}

void main() {
  late RecordingLauncher launcher;
  late Completer<void> permissionResponse;
  late Completer<void> signingResponse;
  late bool allowed;
  late List<http.Request> signingRequests;
  final originalLauncher = UrlLauncherPlatform.instance;

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
        final path = request.url.path;
        Object body = [];
        if (path.endsWith('/household_exhibitor_past_show_reports')) {
          body = [
            for (final name in ['exhibitor_report', 'legs'])
              {
                'artifact_id': name,
                'show_id': 'show-1',
                'show_name': 'Past Show',
                'report_name': name,
                'report_label': name,
                'exhibitor_id': 'exhibitor-1',
                'exhibitor_name': 'Test Exhibitor',
              },
          ];
        } else if (path.endsWith('/household_exhibitor_report_download_info')) {
          await permissionResponse.future;
          final artifact = jsonDecode(request.body)['p_artifact_id'];
          body = allowed
              ? [
                  {
                    'storage_bucket': 'reports',
                    'storage_path': '$artifact.pdf',
                  },
                ]
              : [];
        } else if (path.contains('/object/sign/')) {
          signingRequests.add(request);
          await signingResponse.future;
          body = {'signedURL': '/object/sign/reports/test.pdf?token=test'};
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

  setUp(() {
    launcher = RecordingLauncher();
    UrlLauncherPlatform.instance = launcher;
    allowed = true;
    signingRequests = [];
  });

  tearDownAll(() async {
    UrlLauncherPlatform.instance = originalLauncher;
    await Supabase.instance.dispose();
  });

  Future<void> openReports(WidgetTester tester) async {
    permissionResponse = Completer<void>();
    signingResponse = Completer<void>();
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: ExhibitorPastReportsScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Past Show'));
    await tester.pumpAndSettle();
  }

  for (var index = 0; index < 2; index++) {
    testWidgets(
      'download $index opens same tab after delayed authorization and signing',
      (tester) async {
        await openReports(tester);
        await tester.tap(find.byTooltip('Download').at(index));
        await tester.pump(const Duration(seconds: 2));
        expect(launcher.calls, isEmpty);
        expect(signingRequests, isEmpty);
        permissionResponse.complete();
        await tester.pump(const Duration(seconds: 2));
        expect(signingRequests, hasLength(1));
        expect(jsonDecode(signingRequests.single.body)['expiresIn'], 300);
        expect(launcher.calls, isEmpty);
        signingResponse.complete();
        await tester.pumpAndSettle();
        expect(launcher.calls, hasLength(1));
        expect(launcher.calls.single.options.webOnlyWindowName, '_self');
        expect(launcher.calls.single.url, contains('?token=test'));
      },
    );
  }

  testWidgets('unavailable report does not sign or launch a URL', (
    tester,
  ) async {
    allowed = false;
    await openReports(tester);
    await tester.tap(find.byTooltip('Download').first);
    permissionResponse.complete();
    await tester.pumpAndSettle();
    expect(signingRequests, isEmpty);
    expect(launcher.calls, isEmpty);
    expect(
      find.textContaining('Report is not available for download.'),
      findsOneWidget,
    );
  });
}
