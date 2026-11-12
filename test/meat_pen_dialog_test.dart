@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/enter_show_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
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
      httpClient: MockClient((r) async {
        Object data = [];
        if (r.url.path.endsWith('/breeds')) {
          expect(r.url.queryParameters['species'], 'eq.rabbit');
          expect(r.url.queryParameters['class_system'], 'eq.six');
          expect(r.url.queryParameters['is_active'], 'eq.true');
          expect(r.url.queryParameters['local_show_id'], 'is.null');
          data = [
            {
              'id': 'cal',
              'name': 'Californian',
              'species': 'rabbit',
              'class_system': 'six',
            },
          ];
        } else if (r.url.path.endsWith('/varieties')) {
          expect(r.url.queryParameters['breed_id'], 'eq.cal');
          data = [
            {'id': 'standard', 'name': 'Standard'},
          ];
        } else {
          expect(r.url.path.endsWith('/show_varieties'), true);
        }
        return http.Response(
          jsonEncode(data),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('master six-class meat pen selection at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      MeatPenInput? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Theme(
            data: AppTheme.onGradientTheme(AppTheme.lightTheme),
            child: Scaffold(
              backgroundColor: AppColors.pageBackground,
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await showMeatPenDialog(
                      context,
                      showId: 'meat-only',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final dialogContext = tester.element(find.byType(AlertDialog));
      final theme = Theme.of(dialogContext);
      final foreground = theme.textTheme.bodyMedium!.color!;
      final background = theme.dialogTheme.backgroundColor!;
      final a = foreground.computeLuminance(),
          b = background.computeLuminance();
      expect(
        (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05)),
        greaterThanOrEqualTo(4.5),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Dutch');
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(
        find.text('Please select a valid breed from the list.'),
        findsOneWidget,
      );
      await tester.enterText(fields.at(0), 'Calif');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Californian').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), 'Standard');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standard').last);
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(2), 'mp1');
      await tester.enterText(fields.at(3), 'mp2');
      await tester.enterText(fields.at(4), 'mp3');
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(
        saved?.breed,
        'Californian',
        reason:
            tester
                .widgetList<TextField>(find.byType(TextField))
                .map((f) => f.controller?.text)
                .join('|') +
            tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data)
                .join('|'),
      );
      expect(saved?.variety, 'Standard');
      expect(saved?.tattoos, ['MP1', 'MP2', 'MP3']);
      expect(tester.takeException(), isNull);
    });
  }
}
