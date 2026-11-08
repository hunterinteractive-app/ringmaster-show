import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/cart_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  testWidgets(
    'failed fee preview blocks payment; retry displays the full total',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var previews = 0;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await Supabase.initialize(
          url: 'https://cart-fixture.invalid',
          anonKey: 'test',
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage(),
          ),
          httpClient: MockClient((req) async {
            final path = req.url.path;
            Object data = [];
            var status = 200;
            if (path.endsWith('/shows')) {
              data = {
                'id': 'show',
                'name': 'Test Show',
                'start_date': '2099-11-12',
                'entry_close_at': '2099-11-11T23:30:00Z',
                'online_payment_fee_mode': 'pass_to_exhibitor',
              };
            } else if (path.endsWith('/show_fee_settings')) {
              data = {'currency': 'USD', 'fee_per_entry': 5};
            } else if (path.endsWith('/show_sections')) {
              data = [
                {
                  'id': 'section',
                  'kind': 'open',
                  'letter': 'A',
                  'display_name': 'Open A',
                },
              ];
            } else if (path.endsWith('/show_section_fee_settings')) {
              data = [
                {
                  'section_id': 'section',
                  'fee_per_entry': 5,
                  'fee_per_show': 0,
                  'fur_fee': 0,
                },
              ];
            } else if (path.endsWith('/entry_cart_items')) {
              data = List.generate(
                2,
                (i) => {
                  'id': 'item$i',
                  'exhibitor_id': 'exhibitor',
                  'section_id': 'section',
                  'animal_id': 'animal$i',
                  'species': 'rabbit',
                  'breed': 'Tan',
                  'variety': 'Black',
                  'sex': 'buck',
                  'tattoo': '$i',
                  'class_name': 'Senior',
                  'is_fur': false,
                },
              );
            } else if (path.endsWith('/exhibitors')) {
              data = [
                {'id': 'exhibitor', 'showing_name': 'Test Exhibitor'},
              ];
            } else if (path.endsWith('/get_show_checkout_options')) {
              data = {
                'payment_timing_mode': 'online_only',
                'allow_online': true,
                'allow_at_show': false,
                'require_online_payment': true,
                'default_online_provider': 'stripe',
                'providers': [
                  {'provider': 'stripe', 'enabled': true, 'ready': true},
                ],
              };
            } else if (path.endsWith('/get_show_addons')) {
              data = {'items': []};
            } else if (path.endsWith('/entry_cart_discounts')) {
              data = {
                'codes': [],
                'balances': [
                  {
                    'exhibitor_id': 'exhibitor',
                    'entries_subtotal_cents': 1000,
                    'discount_cents': 0,
                    'balance_due_cents': 1000,
                  },
                ],
              };
            } else if (path.endsWith('/payment-quote-preview')) {
              previews++;
              status = previews == 1 ? 400 : 200;
              data = previews == 1
                  ? {'error': 'Invalid action.'}
                  : {
                      'provider': 'stripe',
                      'currency': 'usd',
                      'base_total_cents': 1000,
                      'online_processing_fee_cents': 84,
                      'amount_due_cents': 1084,
                    };
            }
            return http.Response(
              jsonEncode(data),
              status,
              headers: {'content-type': 'application/json'},
              request: req,
            );
          }),
        );
      });
      addTearDown(() => Supabase.instance.dispose());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CartScreen(
            cartId: 'cart',
            showId: 'show',
            showName: 'Test Show',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to calculate the online total. Please retry.'),
        findsOneWidget,
      );
      expect(find.text(r'Total due online: $10.00'), findsNothing);
      final disabled = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Awaiting online total'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(disabled.onPressed, isNull);
      await tester.ensureVisible(find.text('Retry payment total'));
      await tester.tap(find.text('Retry payment total'));
      await tester.pumpAndSettle();
      expect(previews, 2);
      expect(find.text(r'Total due online: $10.84'), findsOneWidget);
      expect(find.text(r'Online Payment Fee: $0.84'), findsOneWidget);
      final ready = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(r'Pay $10.84 Online'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(ready.onPressed, isNotNull);
      // Do not click Pay: this test only verifies the preview and recovery state.
      await tester.pump(const Duration(minutes: 5));
    },
  );
}
