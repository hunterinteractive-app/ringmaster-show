import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_checkin_settings_dialog.dart';
import 'package:ringmaster_show/screens/exhibitor_checkin_portal_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  const screenshots = bool.fromEnvironment('CHECKIN_SCREENSHOTS');
  final captureKey = GlobalKey();
  Future<void> capture(WidgetTester tester, String name) async {
    if (!screenshots) return;
    await tester.pumpAndSettle();
    final boundary =
        captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      await File('/tmp/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  var failLoad = false, locked = false, completed = false;
  final writes = <Map<String, dynamic>>[];
  setUpAll(() async {
    {
      // Use the app font for representative enlarged-text layout checks.
      final loader = FontLoader('Roboto')
        ..addFont(
          File(
            'assets/fonts/NotoSans-Regular.ttf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await loader.load();
    }
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
        dynamic result;
        final path = request.url.path;

        if (failLoad && path.endsWith('/shows')) {
          return http.Response(
            '{"message":"unavailable","code":"503"}',
            503,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/shows')) {
          result = {'is_locked': locked, 'finalized_at': null};
        } else if (path.endsWith('/show_checkin_settings')) {
          if (request.method == 'GET') {
            result = {
              'is_enabled': true,
              'require_initials': true,
              'entry_edit_permissions': {'breed': 'approval'},
              'entry_edit_fee_cents': {'breed': 250},
            };
          } else {
            writes.add(jsonDecode(request.body));
            result = null;
          }
        } else if (path.endsWith('/regenerate_show_checkin_portal_token')) {
          result = 'fixture-token';
        } else if (path.endsWith('/get_exhibitor_checkin_portal_show')) {
          result = {'show_name': 'Fixture Show'};
        } else if (path.endsWith('/authenticate_exhibitor_checkin')) {
          result = {'session_token': 'fixture-session'};
        } else if (path.endsWith('/get_exhibitor_checkin_portal_data')) {
          result = {
            'show': {'name': 'Fixture Show'},
            'exhibitor': {'name': 'Test Exhibitor', 'number': '123'},
            'entries': [
              {
                'id': 'entry-1',
                'tattoo': 'TEST123',
                'breed': 'American Fuzzy Lop',
                'variety': 'Broken',
                'class_name': 'Senior',
                'sex': 'Doe',
                'show_label': 'Open A',
                'status': 'submitted',
              },
            ],
            'checkin': {
              'status': completed ? 'completed' : 'in_progress',
              'require_initials': true,
              'require_signature': true,
            },
          };
        } else if (path.endsWith('/get_exhibitor_checkin_payment_status')) {
          result = {'balance_due_cents': 0, 'currency': 'usd'};
        } else if (path.endsWith('/get_exhibitor_checkin_change_requests')) {
          result = [];
        } else if (path.endsWith('/complete_exhibitor_checkin')) {
          writes.add(jsonDecode(request.body));
          completed = true;
          result = {'status': 'completed'};
        } else {
          throw StateError('Unexpected request: ${request.method} $path');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() {
    failLoad = false;
    locked = false;
    completed = false;
    writes.clear();
  });
  tearDownAll(() async => Supabase.instance.dispose());
  Future<void> phone(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settings(WidgetTester tester, {double scale = 1}) async {
    await phone(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ShowCheckinSettingsDialog.open(
              context,
              showId: 'fixture',
              showName: 'Fixture Show',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      scale: scale,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'settings save current values, QR and light field contrast at phone size',
    (tester) async {
      await settings(tester, scale: 1.3);
      await capture(tester, 'checkin-settings-phone');
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, AppColors.surface);
      for (final element in find.byType(TextField).evaluate()) {
        final t = Theme.of(element);
        expect(t.textTheme.bodyLarge!.color, AppColors.text);
      }
      await tap(tester, 'Save Settings');
      expect(writes.single['entry_edit_permissions']['breed'], 'approval');
      expect(writes.single['entry_edit_fee_cents']['breed'], 250);
      expect(writes.single['require_initials'], true);
      await tap(tester, 'Generate New QR Code');
      await capture(tester, 'checkin-settings-qr-phone');
      expect(
        find.text(
          'https://checkin.ringmasterone.com/#/checkin?token=fixture-token',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('load failures block saving and can retry', (tester) async {
    failLoad = true;
    await settings(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save Settings'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(writes, isEmpty);
    failLoad = false;
    await tap(tester, 'Retry');
    await tap(tester, 'Save Settings');
    expect(writes, hasLength(1));
  });
  testWidgets('locked show remains view only', (tester) async {
    locked = true;
    await settings(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save Settings'),
          )
          .onPressed,
      isNull,
    );
    expect(writes, isEmpty);
  });
  testWidgets('exhibitor verifies and completes without sending email', (
    tester,
  ) async {
    await phone(
      tester,
      const ExhibitorCheckinPortalScreen(initialToken: 'fixture-token'),
      scale: 1.3,
    );
    await tester.enterText(find.byType(TextField).at(0), '123');
    await tester.enterText(find.byType(TextField).at(1), 'Exhibitor');
    await tap(tester, 'Continue');
    await capture(tester, 'checkin-exhibitor-review-phone');
    await tap(tester, 'I confirm these entries are correct.');
    final initials = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Your initials',
    );
    final signature = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Typed signature',
    );
    await tester.ensureVisible(initials);
    await tester.enterText(initials, 'TE');
    await tester.ensureVisible(signature);
    await tester.enterText(signature, 'Test Exhibitor');
    await capture(tester, 'checkin-exhibitor-confirm-phone');
    await tap(tester, 'Complete Check-In');
    expect(find.text('Check-In Complete'), findsOneWidget);
    expect(writes.single['p_receipt_preference'], 'no_receipt');
    expect(writes.single['p_signature_data'], 'Test Exhibitor');
    expect(tester.takeException(), isNull);
  });
}
