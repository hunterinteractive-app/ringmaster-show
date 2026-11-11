import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/closeout/widgets/manual_report_delivery_panel.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  final calls = <String>[];
  final deliveries = <Map<String, dynamic>>[];
  var generation = 1;
  var missingContact = false;
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
      httpClient: MockClient((request) async {
        final path = request.url.path.split('/').last;
        calls.add(path);
        Object? value;
        if (path == 'show_report_artifacts') {
          value = [
            for (final id in ['noemail', 'online'])
              for (final type in ['exhibitor_report', 'legs'])
                {
                  'id': '$id-$type',
                  'report_name': type,
                  'artifact_status': 'generated',
                  'generation': generation,
                  'is_current': true,
                  'metadata': {
                    'exhibitor_id': id,
                    'exhibitor_email': 'old@example.test',
                  },
                  'section_ids': ['section'],
                },
          ];
        } else if (path == 'exhibitors') {
          value = [
            if (!missingContact)
              {
                'id': 'noemail',
                'showing_name': 'Offline Exhibitor',
                'email': null,
                'address_line1': '1 Test Street',
                'city': 'Town',
                'state': 'IN',
                'zip': '46000',
              },
            {
              'id': 'online',
              'showing_name': 'Online Exhibitor',
              'email': 'fixture@example.test',
            },
          ];
        } else if (path == 'report_manual_deliveries') {
          value = deliveries;
        } else if (path == 'queue_manual_report_print_pack') {
          value = 'pack';
        } else if (path == 'exhibitor_print_packs') {
          value = {
            'id': 'pack',
            'artifact_status': 'generated',
            'file_name': 'packet.pdf',
          };
        } else if (path == 'mark_report_manual_delivery') {
          final body = jsonDecode(request.body) as Map;
          deliveries.clear();
          if (body['p_method'] != 'pending') {
            for (final a in body['p_artifacts']) {
              deliveries.add({
                'artifact_id': a['id'],
                'generation': a['generation'],
                'method': body['p_method'],
              });
            }
          }
        } else {
          throw StateError('Unexpected request: $path');
        }
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    calls.clear();
    deliveries.clear();
    generation = 1;
    missingContact = false;
  });
  Future<void> open(WidgetTester tester, {double width = 1000}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showManualReportDelivery(
                context,
                showId: 'show',
                beforeEmail: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows only no-email exhibitors and never sends email or marks delivery on open',
    (t) async {
      await open(t);
      expect(find.text('Offline Exhibitor'), findsOneWidget);
      expect(find.text('Online Exhibitor'), findsNothing);
      expect(
        find.text('1 exhibitors without email • 1 print/mail outstanding'),
        findsOneWidget,
      );
      expect(
        calls.where(
          (c) => c.startsWith('send') || c == 'mark_report_manual_delivery',
        ),
        isEmpty,
      );
      await t.tap(find.text('Continue with emails'));
      await t.pumpAndSettle();
      expect(calls.where((c) => c.startsWith('send')), isEmpty);
    },
  );
  testWidgets(
    'packet preparation does not imply delivery; marking requires confirmation',
    (t) async {
      await open(t);
      await t.tap(find.text('Prepare print packet'));
      await t.pumpAndSettle();
      expect(find.text('Print reports'), findsOneWidget);
      expect(deliveries, isEmpty);
      await t.ensureVisible(find.text('Mark mailed'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mark mailed'));
      await t.pumpAndSettle();
      expect(find.text('Confirm report delivery'), findsOneWidget);
      expect(deliveries, isEmpty);
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(deliveries.length, 2);
      expect(
        find.text('1 exhibitors without email • 0 print/mail outstanding'),
        findsOneWidget,
      );
      generation = 2;
      await t.ensureVisible(find.text('Refresh'));
      await t.tap(find.text('Refresh'));
      await t.pumpAndSettle();
      expect(
        find.text('1 exhibitors without email • 1 print/mail outstanding'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'phone dialog and nested confirmation remain readable without overflow',
    (t) async {
      await open(t, width: 390);
      await t.ensureVisible(find.text('Mark handed out'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mark handed out'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final dialog = t.widget<AlertDialog>(find.byType(AlertDialog));
      final theme = Theme.of(t.element(find.byWidget(dialog)));
      expect(theme.colorScheme.onSurface.computeLuminance(), lessThan(.2));
      expect(
        theme.dialogTheme.backgroundColor!.computeLuminance(),
        greaterThan(.7),
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(deliveries, isEmpty);
    },
  );
  testWidgets(
    'missing current contact blocks packet actions instead of using stale email',
    (t) async {
      missingContact = true;
      await open(t);
      expect(
        find.textContaining('Some exhibitor contacts could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('Prepare print packet'), findsNothing);
    },
  );
}
