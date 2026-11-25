// Run with flutter test --platform chrome.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/my_entries_screen.dart';
import 'package:ringmaster_show/screens/cart_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  testWidgets(
    'My Entries adds selected fur sections and opens returned checkout',
    (tester) async {
      const owner = 'aaaaaaaa-0000-4000-8000-000000000001';
      Map<String, dynamic>? saved;
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(
        url: 'https://fur-fixture.invalid',
        anonKey: 'fixture',
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          detectSessionInUri: false,
          localStorage: EmptyLocalStorage(),
        ),
        httpClient: MockClient((req) async {
          final path = req.url.path.split('/').last;
          Object? data = [];
          if (path == 'exhibitors') {
            data = [
              {
                'id': 'ex',
                'display_name': 'Fur Exhibitor',
                'owner_user_id': owner,
              },
            ];
          }
          if (path == 'entries') {
            data = [
              {
                'id': 'entry',
                'show_id': 'show',
                'exhibitor_id': 'ex',
                'animal_id': 'animal',
                'species': 'rabbit',
                'tattoo': 'FUR1',
                'breed': 'Havana',
                'variety': 'Black',
                'sex': 'Buck',
                'class_name': 'Senior',
                'status': 'submitted',
                'is_fur': false,
                'section_id': 'a',
                'exhibitor_user_id': owner,
              },
            ];
          }
          if (path == 'shows') {
            final show = {
              'id': 'show',
              'name': 'Holiday Show',
              'start_date': '2099-12-01',
              'entry_open_at': '2020-01-01',
              'entry_close_at': '2099-11-30',
              'is_locked': false,
            };
            data = req.headers['Accept'] == 'application/vnd.pgrst.object+json'
                ? show
                : [show];
          }
          if (path == 'show_sections') {
            data = [
              {
                'id': 'a',
                'show_id': 'show',
                'display_name': 'Youth A',
                'kind': 'youth',
                'letter': 'A',
              },
            ];
          }
          if (path == 'exhibitor_fur_additions') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            expect(body['p_entry_id'], 'entry');
            if (body.containsKey('p_section_ids')) {
              saved = body;
              data = {
                'cart_id': 'fur-cart',
                'show_id': 'show',
                'show_name': 'Holiday Show',
              };
            } else {
              data = {
                'show_id': 'show',
                'show_name': 'Holiday Show',
                'tattoo': 'FUR1',
                'currency': 'USD',
                'sections': [
                  {'id': 'a', 'label': 'Youth A', 'fee_cents': 200},
                  {'id': 'b', 'label': 'Youth B', 'fee_cents': 200},
                ],
              };
            }
          }
          if (path == 'entry_carts' &&
              req.headers['Accept'] == 'application/vnd.pgrst.object+json') {
            data = {
              'id': 'fur-cart',
              'status': 'active',
              'payment_status': 'unpaid',
            };
          }
          if (path == 'show_fee_settings') data = {'currency': 'USD'};
          if (path == 'get_show_checkout_options') {
            data = {
              'payment_timing_mode': 'online_only',
              'allow_online': true,
              'allow_at_show': false,
              'require_online_payment': true,
              'providers': [],
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
      addTearDown(() => Supabase.instance.dispose());
      String segment(Object v) =>
          base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      await Supabase.instance.client.auth.recoverSession(
        jsonEncode({
          'access_token':
              '${segment({'alg': 'HS256'})}.${segment({'sub': owner, 'exp': exp, 'role': 'authenticated'})}.fixture',
          'refresh_token': 'fixture',
          'token_type': 'bearer',
          'expires_at': exp,
          'expires_in': 3600,
          'user': {
            'id': owner,
            'aud': 'authenticated',
            'email': 'fixture@example.invalid',
            'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {},
          },
        }),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> render() async {
        for (var n = 0; n < 20; n++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const MyEntriesScreen()),
      );
      await render();
      // Expand the show and the exhibitor's entry groups as needed.
      for (
        var n = 0;
        n < 8 && find.text('Add Fur/Wool').evaluate().isEmpty;
        n++
      ) {
        final tiles = find.byType(ExpansionTile).evaluate().toList();
        var expanded = false;
        for (final element in tiles) {
          final tile = element.widget as ExpansionTile;
          final finder = find.byWidget(tile.title);
          if (finder.evaluate().isNotEmpty) {
            await tester.ensureVisible(finder);
            await tester.tap(finder);
            await render();
            if (find.text('Add Fur/Wool').evaluate().isNotEmpty) {
              expanded = true;
              break;
            }
          }
        }
        if (expanded) break;
      }
      final add = find.text('Add Fur/Wool');
      expect(add, findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await render();
      await tester.ensureVisible(add);
      await render();
      await tester.tap(add);
      await render();
      await tester.tap(find.text('Select all available sections'));
      await tester.pump();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await render();
      await tester.tap(find.text('Colored').last);
      await render();
      await tester.tap(find.text('Continue to checkout'));
      await render();
      expect(saved?['p_section_ids'], unorderedEquals(['a', 'b']));
      expect(saved?['p_fur_variety'], 'Colored');
      expect(
        tester.widget<CartScreen>(find.byType(CartScreen)).cartId,
        'fur-cart',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 5));
    },
  );
}
