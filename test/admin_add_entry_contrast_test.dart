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
        expect(
          request.method,
          'GET',
          reason: 'Contrast review must not save entries',
        );
        final value = request.url.path.endsWith('/shows')
            ? {'start_date': '2027-01-01'}
            : [];
        return http.Response(
          jsonEncode(value),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  double ratio(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  Color color(WidgetTester tester, Finder f) {
    final t = tester.widget<Text>(f);
    return t.style?.color ??
        DefaultTextStyle.of(tester.element(f)).style.color!;
  }

  testWidgets(
    'actual phone entry form labels, dropdown and validation contrast',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => buildAdminAddEntrySheet(
                context,
                showId: 'fixture',
                sections: [
                  {
                    'id': 'a',
                    'letter': 'A',
                    'display_name': 'Open A',
                    'kind': 'open',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.byType(SingleChildScrollView).first;
      for (final text in [
        'Add Entry',
        'Show Letters / Sections',
        'Add New Exhibitor',
      ]) {
        final f = find.text(text);
        for (final bg in AppGradients.page.colors) {
          expect(
            ratio(Color.alphaBlend(color(tester, f), bg), bg),
            greaterThanOrEqualTo(4.5),
            reason: text,
          );
        }
      }
      expect(
        ratio(
          color(tester, find.text('Select at least one section.')),
          Colors.white,
        ),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.text('Add New Exhibitor'));
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        final f = find.byWidget(field);
        final theme = Theme.of(tester.element(f));
        final fg = field.style?.color ?? theme.textTheme.bodyLarge!.color!;
        expect(
          ratio(fg, AppColors.surface),
          greaterThanOrEqualTo(4.5),
          reason: field.decoration?.labelText,
        );
      }
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Showing Name',
      );
      await tester.ensureVisible(nameField);
      await tester.pumpAndSettle();
      await tester.tap(nameField);
      await tester.pumpAndSettle();
      expect(
        ratio(color(tester, find.text('Showing Name')), AppColors.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'Focused field label',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final type = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Exhibitor Type',
      );
      await tester.ensureVisible(type);
      await tester.pumpAndSettle();
      await tester.tap(type);
      await tester.pumpAndSettle();
      expect(
        ratio(color(tester, find.text('Youth').last), AppColors.surface),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.text('Youth').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.drag(scroll, const Offset(0, 5000));
      await tester.pumpAndSettle();
      final errors = find.text('Select at least one section.');
      expect(errors, findsNWidgets(2));
      expect(
        ratio(color(tester, errors.first), AppColors.dangerBg),
        greaterThanOrEqualTo(4.5),
      );
      final containers = tester.widgetList<Container>(
        find.ancestor(of: errors.first, matching: find.byType(Container)),
      );
      expect(
        containers.any(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == AppColors.dangerBg,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
