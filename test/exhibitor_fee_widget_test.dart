import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/show_fees_dialog.dart';
import 'package:ringmaster_show/screens/cart_screen.dart';

void main() {
  var entitled = true;
  var feeOnly = false;
  Map<String, dynamic>? saved;
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
        final path = request.url.path;
        Object? value;
        if (path.endsWith('can_configure_best_opposite_final_award')) {
          value = entitled;
        } else if (path.endsWith('get_show_checkout_options')) {
          value = {
            'payment_timing_mode': 'pay_at_show_only',
            'allow_at_show': true,
            'allow_online': false,
            'providers': [],
          };
        } else if (path.endsWith('get_cart_exhibitor_fees')) {
          value = [
            for (final id in feeOnly ? ['ex1'] : ['ex1', 'ex2'])
              {
                'exhibitor_id': id,
                'label': 'Facility Fee',
                'amount_cents': 750,
              },
          ];
        } else if (path.endsWith('/shows')) {
          value = {
            'id': 'show',
            'name': 'Test Show',
            'is_locked': false,
            'finalized_at': null,
            'entry_close_at': '2030-01-01T00:00:00Z',
          };
        } else if (path.endsWith('/show_fee_settings')) {
          if (request.method == 'POST') {
            saved = Map<String, dynamic>.from(jsonDecode(request.body));
          }
          value = {
            'show_id': 'show',
            'currency': 'USD',
            'multi_show_discount_value': 0,
            'exhibitor_fee_enabled': false,
            'exhibitor_fee_amount': 0,
            'exhibitor_fee_label': 'Exhibitor Fee',
          };
        } else if (path.endsWith('/show_sections')) {
          value = [
            for (final id in ['s1', 's2'])
              {
                'id': id,
                'kind': 'open',
                'letter': id == 's1' ? 'A' : 'B',
                'display_name': id == 's1' ? 'Open A' : 'Open B',
                'sort_order': 1,
              },
          ];
        } else if (path.endsWith('/show_section_fee_settings')) {
          value = [
            for (final id in ['s1', 's2'])
              {
                'section_id': id,
                'fee_per_entry': 10,
                'fee_per_show': 0,
                'fur_fee': 0,
              },
          ];
        } else if (path.endsWith('/entry_cart_items')) {
          value = feeOnly
              ? [
                  {
                    'id': 'carrier',
                    'exhibitor_id': 'ex1',
                    'section_id': 's1',
                    'is_exhibitor_fee_carrier': true,
                    'tattoo': 'EXHIBITOR-FEE',
                  },
                ]
              : [
                  for (final ex in ['ex1', 'ex2'])
                    for (final sec in ['s1', 's2'])
                      {
                        'id': '$ex-$sec',
                        'exhibitor_id': ex,
                        'section_id': sec,
                        'is_fur': false,
                        'tattoo': ex,
                        'species': 'rabbit',
                        'breed': 'Dutch',
                        'class_name': 'Senior',
                        'sex': 'Buck',
                      },
                ];
        } else if (path.endsWith('/exhibitors')) {
          value = [
            {'id': 'ex1', 'display_name': 'First Exhibitor'},
            {'id': 'ex2', 'display_name': 'Second Exhibitor'},
          ];
        } else if (path.contains('/functions/')) {
          value = {'status': 'not_connected'};
        } else if (request.method == 'GET') {
          value = null;
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
    entitled = true;
    feeOnly = false;
    saved = null;
  });
  Future<void> size(WidgetTester tester, {double width = 1200}) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await size(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ShowFeesDialog.open(
                context,
                showId: 'show',
                showName: 'Test Show',
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

  testWidgets('selected secretary can save a custom name and amount', (
    tester,
  ) async {
    await openSettings(tester);
    expect(find.text('One-Time Exhibitor Fee'), findsOneWidget);
    await tester.ensureVisible(find.text('Charge once per exhibitor number'));
    await tester.tap(find.text('Charge once per exhibitor number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Fee name'),
      'Facility Fee',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount per exhibitor number'),
      '7.50',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(saved?['exhibitor_fee_enabled'], true);
    expect(saved?['exhibitor_fee_label'], 'Facility Fee');
    expect(saved?['exhibitor_fee_amount'], 7.5);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unselected secretary does not see the setting', (tester) async {
    entitled = false;
    await openSettings(tester);
    expect(find.text('One-Time Exhibitor Fee'), findsNothing);
    expect(find.text('Entry Fees by Show Section'), findsOneWidget);
  });
  testWidgets('cart shows one custom fee per number across sections', (
    tester,
  ) async {
    await size(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: CartScreen(cartId: 'cart', showId: 'show', showName: 'Test Show'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(r'Total due at show: $55.00'), findsOneWidget);
    expect(
      find.textContaining('Facility Fee — First Exhibitor'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Facility Fee — Second Exhibitor'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('fee-only cart hides the carrier and shows the fee total', (
    tester,
  ) async {
    feeOnly = true;
    await size(tester, width: 430);
    await tester.pumpWidget(
      const MaterialApp(
        home: CartScreen(cartId: 'cart', showId: 'show', showName: 'Test Show'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('EXHIBITOR-FEE'), findsNothing);
    expect(find.text(r'Total due at show: $7.50'), findsOneWidget);
    expect(find.text('Confirm Fee (Pay at Show)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
