import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/admin/admin_entry_management_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  late Map<String, dynamic> exhibitor;
  late List<Map<String, dynamic>> animals;
  late List<Map<String, dynamic>> entries;
  const breed = {
    'id': 'lop',
    'name': 'Holland Lop',
    'species': 'rabbit',
    'class_system': '4',
    'is_active': true,
  };
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
        final table = request.url.path.split('/').last;
        final query = request.url.queryParameters;
        dynamic value = <dynamic>[];
        if (request.method == 'POST' && table == 'animals') {
          final row = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          row['id'] = 'animal-${animals.length + 1}';
          animals.add(row);
          value = row;
        } else if (request.method == 'POST' && table == 'entries') {
          value = (jsonDecode(request.body) as List).map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            row['id'] = 'entry-${entries.length + 1}';
            entries.add(row);
            return row;
          }).toList();
        } else if (request.method == 'GET') {
          switch (table) {
            case 'shows':
              value = {'start_date': '2027-01-01'};
            case 'exhibitors':
              value = [exhibitor];
            case 'breeds':
              value = [breed];
            case 'animals':
              value = animals;
            case 'entries':
              value = entries
                  .where(
                    (row) =>
                        query['animal_id'] == 'eq.${row['animal_id']}' &&
                        query['section_id'] == 'eq.${row['section_id']}',
                  )
                  .toList();
          }
        } else if (!table.startsWith('search_')) {
          fail('Unexpected write: ${request.method} ${request.url}');
        }
        return http.Response(
          jsonEncode(value),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> choose<T extends Object>(
    WidgetTester tester,
    String label,
    T value,
  ) async {
    final controller = tester.widget<TextField>(field(label)).controller;
    final widget = tester.widget<RawAutocomplete<T>>(
      find.byWidgetPredicate(
        (w) => w is RawAutocomplete<T> && w.textEditingController == controller,
      ),
    );
    widget.onSelected!(value);
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, String text) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  for (final owner in ['owner', '']) {
    testWidgets(
      'secretary same-tattoo animals stay separate (${owner.isEmpty ? 'show-local' : 'account'})',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        exhibitor = {
          'id': 'exhibitor',
          'showing_name': 'Test Exhibitor',
          'type': 'adult',
          'owner_user_id': owner,
        };
        animals = [];
        entries = [];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => buildAdminAddEntrySheet(
                  context,
                  showId: 'show',
                  sections: [
                    {
                      'id': 'a',
                      'letter': 'A',
                      'display_name': 'Open A',
                      'kind': 'open',
                    },
                    {
                      'id': 'b',
                      'letter': 'B',
                      'display_name': 'Open B',
                      'kind': 'open',
                    },
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final tile
            in tester
                .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                .toList()) {
          tile.onChanged!(true);
        }
        await choose<Map<String, dynamic>>(tester, 'Exhibitor', exhibitor);
        for (final className in ['Junior', 'Senior']) {
          await press(tester, 'Add New Animal');
          await tester.enterText(field('Tattoo'), 'j');
          await choose<Map<String, dynamic>>(tester, 'Breed', breed);
          await choose<Map<String, dynamic>>(tester, 'Variety', {
            'id': 'lop_solid',
            'name': 'Solid',
          });
          await choose<String>(tester, 'Sex', 'Buck');
          await choose<String>(tester, 'Class', className);
          await press(tester, 'Save & Add Another');
          expect(tester.takeException(), isNull);
          expect(entries.length, className == 'Junior' ? 2 : 4);
        }
        expect(animals.length, 2);
        expect(animals.map((row) => row['tattoo']), ['J', 'J']);
        expect(animals.map((row) => row['owner_user_id']), [
          owner.isEmpty ? null : owner,
          owner.isEmpty ? null : owner,
        ]);
        expect(
          animals.every((row) => row['exhibitor_id'] == 'exhibitor'),
          isTrue,
        );
        expect(entries.map((row) => row['animal_id']), [
          'animal-1',
          'animal-1',
          'animal-2',
          'animal-2',
        ]);
        expect(entries.map((row) => row['class_name']), [
          'Junior',
          'Junior',
          'Senior',
          'Senior',
        ]);
        expect(entries.map((row) => row['section_id']), ['a', 'b', 'a', 'b']);

        // Reopen the sheet and select the SAME saved rabbit: still a duplicate.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => buildAdminAddEntrySheet(
                  context,
                  showId: 'show',
                  sections: [
                    {
                      'id': 'a',
                      'letter': 'A',
                      'display_name': 'Open A',
                      'kind': 'open',
                    },
                    {
                      'id': 'b',
                      'letter': 'B',
                      'display_name': 'Open B',
                      'kind': 'open',
                    },
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final tile
            in tester
                .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                .toList()) {
          tile.onChanged!(true);
        }
        await tester.pumpAndSettle();
        await choose<Map<String, dynamic>>(tester, 'Exhibitor', exhibitor);
        final saved = tester
            .widget<DropdownButtonFormField<Map<String, dynamic>>>(
              find.byWidgetPredicate(
                (w) =>
                    w is DropdownButtonFormField<Map<String, dynamic>> &&
                    w.decoration.labelText == 'Saved Animal',
              ),
            );
        final dropdown = tester.widget<DropdownButton<Map<String, dynamic>>>(
          find.byType(DropdownButton<Map<String, dynamic>>),
        );
        saved.onChanged!(dropdown.items!.first.value);
        await tester.pumpAndSettle();
        await choose<String>(tester, 'Class', 'Junior');
        await press(tester, 'Save & Add Another');
        expect(
          find.textContaining('Animal already entered in'),
          findsOneWidget,
        );
        expect(entries.length, 4);
        expect(animals.length, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
