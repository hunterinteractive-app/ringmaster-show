@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/convention_sale_banner.dart';

void main() {
  final data = <String, dynamic>{
    'title': 'Convention token bonus',
    'venue': 'Reno–Sparks Convention Center',
    'enabled': true,
    'active': false,
    'starts_at': '2026-10-26T07:00:00Z',
    'ends_at': '2026-10-27T07:00:00Z',
    'server_now': '2026-10-26T06:59:50Z',
  };
  var reads = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/convention_sale_settings');
        reads++;
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

  testWidgets('header follows start, pause and end while the page stays open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: ConventionSaleBanner()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Convention token bonus'), findsNothing);

    data.addAll({'active': true, 'server_now': '2026-10-26T07:00:01Z'});
    await tester.pump(const Duration(seconds: 11));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Convention token bonus'), findsOneWidget);

    data.addAll({'enabled': false, 'active': false});
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Convention token bonus'), findsNothing);

    data.addAll({
      'enabled': true,
      'active': true,
      'server_now': '2026-10-27T06:59:59Z',
    });
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Convention token bonus'), findsOneWidget);

    data.addAll({'active': false, 'server_now': '2026-10-27T07:00:00Z'});
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Convention token bonus'), findsNothing);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    final disposedReads = reads;
    await tester.pump(const Duration(minutes: 1));
    expect(reads, disposedReads);
  });
}
