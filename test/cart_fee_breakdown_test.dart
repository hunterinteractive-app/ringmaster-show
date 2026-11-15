import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/cart_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

Future<void> initializeFeeCart({
  int officeFeeCents = 1000,
  int perShowFeeCents = 0,
  int exhibitors = 1,
}) async {
  final total = (800 + officeFeeCents + perShowFeeCents) * exhibitors + 5500;
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
      if (path.endsWith('/shows')) {
        data = {
          'id': 'show',
          'name': 'Fee Breakdown Preview',
          'start_date': '2099-11-12',
          'entry_close_at': '2099-11-11T23:30:00Z',
          'online_payment_fee_mode': 'absorb',
        };
      } else if (path.endsWith('/show_fee_settings')) {
        data = {'currency': 'USD', 'fee_per_entry': 8};
      } else if (path.endsWith('/show_sections')) {
        data = [
          {
            'id': 'section',
            'kind': 'youth',
            'letter': 'A',
            'display_name': 'Youth Cavy',
          },
        ];
      } else if (path.endsWith('/show_section_fee_settings')) {
        data = [
          {
            'section_id': 'section',
            'fee_per_entry': 8,
            'fee_per_show': perShowFeeCents / 100,
            'fur_fee': 0,
          },
        ];
      } else if (path.endsWith('/entry_cart_items')) {
        data = List.generate(
          exhibitors,
          (i) => {
            'id': 'item$i',
            'exhibitor_id': 'exhibitor$i',
            'section_id': 'section',
            'animal_id': 'animal$i',
            'species': 'cavy',
            'breed': 'Peruvian',
            'variety': 'Black',
            'sex': 'boar',
            'tattoo': 'A$i',
            'class_name': 'Senior',
            'is_fur': false,
          },
        );
      } else if (path.endsWith('/exhibitors')) {
        data = List.generate(
          exhibitors,
          (i) => {'id': 'exhibitor$i', 'showing_name': 'Exhibitor ${i + 1}'},
        );
      } else if (path.endsWith('/get_show_checkout_options')) {
        data = {
          'payment_timing_mode': 'online_only',
          'allow_online': true,
          'allow_at_show': false,
          'require_online_payment': true,
          'default_online_provider': 'square',
          'providers': [
            {'provider': 'square', 'enabled': true, 'ready': true},
          ],
        };
      } else if (path.endsWith('/get_show_addons')) {
        data = {'items': []};
      } else if (path.endsWith('/get_cart_addons')) {
        data = [
          {
            'id': 'contest',
            'exhibitor_id': 'exhibitor0',
            'name': 'Rabbit/Cavy Showmanship',
            'quantity': 1,
            'unit_price_cents': 500,
          },
          {
            'id': 'pass',
            'exhibitor_id': 'exhibitor0',
            'name': 'Livestock Season Pass',
            'quantity': 1,
            'unit_price_cents': 5000,
          },
        ];
      } else if (path.endsWith('/get_cart_exhibitor_fees')) {
        data = officeFeeCents == 0
            ? []
            : List.generate(
                exhibitors,
                (i) => {
                  'exhibitor_id': 'exhibitor$i',
                  'label': 'Office Fee',
                  'amount_cents': officeFeeCents,
                },
              );
      } else if (path.endsWith('/entry_cart_discounts')) {
        data = {
          'codes': [],
          'balances': List.generate(
            exhibitors,
            (i) => {
              'exhibitor_id': 'exhibitor$i',
              'entries_subtotal_cents': 800,
              // The backend combines both fees in this subtotal.
              'show_fee_subtotal_cents': officeFeeCents + perShowFeeCents,
              'fee_snapshot': officeFeeCents == 0
                  ? {}
                  : {'exhibitor_fee_cents': officeFeeCents},
              'discount_cents': 0,
              'balance_due_cents':
                  800 + officeFeeCents + perShowFeeCents + (i == 0 ? 5500 : 0),
            },
          ),
        };
      } else if (path.endsWith('/payment-quote-preview')) {
        data = {
          'provider': 'square',
          'currency': 'usd',
          'base_total_cents': total,
          'online_processing_fee_cents': 0,
          'amount_due_cents': total,
        };
      }
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json'},
        request: req,
      );
    }),
  );
}

void main() {
  Future<void> openCart(
    WidgetTester tester, {
    int officeFeeCents = 1000,
    int perShowFeeCents = 0,
    int exhibitors = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(
      () => initializeFeeCart(
        officeFeeCents: officeFeeCents,
        perShowFeeCents: perShowFeeCents,
        exhibitors: exhibitors,
      ),
    );
    addTearDown(() => Supabase.instance.dispose());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CartScreen(
          cartId: 'cart',
          showId: 'show',
          showName: 'Fee Breakdown Preview',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'office fee is listed once and the quoted total stays 73 dollars',
    (tester) async {
      await openCart(tester);
      expect(find.textContaining('Per-show fees:'), findsNothing);
      expect(
        find.text(
          r'Office Fee — Exhibitor 1 (once per exhibitor number): $10.00',
        ),
        findsOneWidget,
      );
      expect(find.text('Contests & Add-Ons: USD 55.00'), findsOneWidget);
      expect(find.text(r'Total due online: $73.00'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining(r'1 entries: $8.00'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(r'1 entries: $8.00 • Office Fee (once): $10.00 • = $18.00'),
        findsOneWidget,
      );
      // Display-only verification: never invoke checkout or a real payment.
      await tester.pump(const Duration(minutes: 5));
    },
  );

  testWidgets('genuine per-show fee remains separate from the office fee', (
    tester,
  ) async {
    await openCart(tester, perShowFeeCents: 500);
    expect(find.text(r'Per-show fees: $5.00'), findsOneWidget);
    expect(find.text(r'Total due online: $78.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining(r'1 entries: $8.00'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(
        r'1 entries: $8.00 • Show fees: $5.00 • Office Fee (once): $10.00 • = $23.00',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('shows without an office fee retain their per-show fee', (
    tester,
  ) async {
    await openCart(tester, officeFeeCents: 0, perShowFeeCents: 500);
    expect(find.text(r'Per-show fees: $5.00'), findsOneWidget);
    expect(find.textContaining('Office Fee'), findsNothing);
    expect(find.text(r'Total due online: $68.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining(r'1 entries: $8.00'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(r'1 entries: $8.00 • Show fees: $5.00 • = $13.00'),
      findsOneWidget,
    );
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('each exhibitor gets only their own one-time office fee', (
    tester,
  ) async {
    await openCart(tester, exhibitors: 2);
    expect(find.textContaining('Per-show fees:'), findsNothing);
    expect(
      find.text(
        r'Office Fee — Exhibitor 1 (once per exhibitor number): $10.00',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        r'Office Fee — Exhibitor 2 (once per exhibitor number): $10.00',
      ),
      findsOneWidget,
    );
    expect(find.text(r'Total due online: $91.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Exhibitor 2'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text(r'1 entries: $8.00 • Office Fee (once): $10.00 • = $18.00'),
      findsNWidgets(2),
    );
    await tester.pump(const Duration(minutes: 5));
  });
}
