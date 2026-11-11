import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/admin_resources_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode([
            {
              'id': 'checkin-guide',
              'title': 'Check-In Quick Guide',
              'category': 'Help Guides',
              'mime_type': 'application/pdf',
              'storage_path': 'guides/checkin.pdf',
              'file_name': 'checkin.pdf',
              'sort_order': 0,
            },
          ]),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgets('PDF guide appears with help guides and has no image preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const AdminResourcesScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('RingMaster Show Help Guides'));
    await tester.pumpAndSettle();
    expect(find.text('Check-In Quick Guide'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byTooltip('Preview'), findsNothing);
    final dialogContext = tester.element(find.byType(AlertDialog));
    expect(
      Theme.of(dialogContext).dialogTheme.backgroundColor,
      AppColors.surface,
    );
  });
}
