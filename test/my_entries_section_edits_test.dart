// Run with flutter test --platform chrome.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/my_entries_screen.dart';
import 'package:ringmaster_show/widgets/edit_entry_dialog.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  testWidgets(
    'My Entries keeps rabbit sections together and saves only selected tattoo edits',
    (tester) async {
      const owner = 'aaaaaaaa-0000-4000-8000-000000000001';
      Map<String, dynamic>? saved;
      final entries = <Map<String, dynamic>>[
        for (final section in ['b', 'a'])
          {
            'id': 'entry-$section',
            'show_id': 'show',
            'exhibitor_id': 'ex',
            'animal_id': 'animal',
            'species': 'rabbit',
            'tattoo': 'FUR1',
            'breed': 'Havana',
            'variety': 'Black',
            'sex': 'Buck',
            'class_name': section == 'a' ? 'Senior' : 'Junior',
            'status': 'submitted',
            'is_fur': false,
            'section_id': section,
            'exhibitor_user_id': owner,
          },
      ];
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
            data = entries;
          }
          if (path == 'animals') {
            data = [
              {
                'id': 'animal',
                'species': 'rabbit',
                'tattoo': 'FUR1',
                'breed': 'Havana',
                'variety': 'Black',
                'sex': 'Buck',
              },
            ];
          }
          if (path == 'breeds') {
            data = [
              {
                'id': 'breed',
                'name': 'Havana',
                'species': 'rabbit',
                'class_system': 'four',
              },
            ];
          }
          if (path == 'apply_entry_section_changes') {
            saved = jsonDecode(req.body) as Map<String, dynamic>;
            for (final entry in entries) {
              if ((saved!['p_section_ids'] as List).contains(
                entry['section_id'],
              )) {
                entry.addAll(
                  Map<String, dynamic>.from(saved!['p_changes'] as Map),
                );
                if (saved!['p_is_scratched'] != null) {
                  entry['status'] = saved!['p_is_scratched'] == true
                      ? 'scratched'
                      : 'entered';
                }
              }
            }
            data = {'entry_count': 2};
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
              for (final section in ['b', 'a'])
                {
                  'id': section,
                  'show_id': 'show',
                  'display_name': 'Open ${section.toUpperCase()}',
                  'kind': 'open',
                  'letter': section.toUpperCase(),
                },
            ];
          }
          if ((int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0) >
              0) {
            data = [];
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
        n < 8 && find.text('Edit Entry').evaluate().isEmpty;
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
            if (find.text('Edit Entry').evaluate().isNotEmpty) {
              expanded = true;
              break;
            }
          }
        }
        if (expanded) break;
      }
      final edit = find.text('Edit Entry').first;
      expect(find.text('Edit Entry'), findsNWidgets(2));
      final sectionLabels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.contains('Section:'))
          .toList();
      expect(sectionLabels[0], contains('Section: Open A'));
      expect(sectionLabels[1], contains('Section: Open B'));
      await tester.ensureVisible(edit);
      await render();
      await tester.tap(edit);
      await render();
      await tester.enterText(find.byType(TextField), ' new42 ');
      await tester.tap(find.text('Choose other show sections for these edits'));
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await render();
      await tester.tap(find.text('Select all sections'));
      await tester.pump();
      await tester.tap(find.text('Apply edits 2 sections'));
      await render();
      expect(saved?['p_section_ids'], unorderedEquals(['a', 'b']));
      expect(saved?['p_changes'], {'tattoo': 'NEW42'});
      expect(entries.first['class_name'], 'Junior');
      expect(entries.last['class_name'], 'Senior');
      expect(find.byType(EditEntryDialog), findsNothing);
      final scratch = find.text('Scratch').first;
      await tester.ensureVisible(scratch);
      await render();
      await tester.tap(scratch);
      await render();
      await tester.tap(find.text('Scratch 1 section'));
      await render();
      expect(saved?['p_is_scratched'], true);
      expect(saved?['p_section_ids'], ['a']);
      expect(entries.last['status'], 'scratched');
      expect(entries.first['status'], 'submitted');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 5));
    },
  );
}
