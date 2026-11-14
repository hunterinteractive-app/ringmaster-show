import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/cart_registration_requirements_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    required Future<void> Function(List<Map<String, dynamic>>) save,
    int children = 2,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (dialogContext) => Theme(
                  data: AppTheme.surfaceDialogTheme(Theme.of(dialogContext)),
                  child: CartRegistrationRequirementsDialog(
                    requirements: {
                      'agreement':
                          'I agree to the Houston Livestock Show and Rodeo rules listed in the 2027 Exhibitor Handbook and all terms and conditions listed on the Houston Livestock Show and Rodeo website.',
                      'handbook_url':
                          'https://www.rodeohouston.com/wp-content/uploads/2026/10/2027-Exhibitor-Handbook-V2.pdf',
                      'website_url': 'https://www.rodeohouston.com',
                      'exhibitors': [
                        for (var i = 1; i <= children; i++)
                          {
                            'exhibitor_id': 'kid$i',
                            'name': 'Youth $i',
                            'number': i,
                            'state': 'TX',
                            'school_name': '',
                            'city': '',
                          },
                      ],
                    },
                    save: save,
                  ),
                ),
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

  Future<void> fill(
    WidgetTester tester,
    String id,
    String key,
    String value,
  ) async {
    final field = find.byKey(ValueKey('$id-$key'));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> agree(WidgetTester tester) async {
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'each youth needs school details and an explicit unchecked agreement on a phone',
    (tester) async {
      List<Map<String, dynamic>>? saved;
      await open(tester, save: (schools) async => saved = schools);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('kid1-state')))
            .initialValue,
        'TX',
      );
      await tester.tap(find.text('Continue to checkout'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('School name is required.'), findsNWidgets(2));
      expect(
        find.text('Agreement is required before checkout.'),
        findsOneWidget,
      );
      for (var i = 1; i <= 2; i++) {
        await fill(tester, 'kid$i', 'school_name', ' School $i ');
        await fill(tester, 'kid$i', 'city', ' Houston ');
      }
      await tester.tap(find.text('Continue to checkout'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await agree(tester);
      await tester.tap(find.text('Continue to checkout'));
      await tester.pumpAndSettle();
      expect(saved, [
        {
          'exhibitor_id': 'kid1',
          'school_name': 'School 1',
          'city': 'Houston',
          'state': 'TX',
        },
        {
          'exhibitor_id': 'kid2',
          'school_name': 'School 2',
          'city': 'Houston',
          'state': 'TX',
        },
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Open checkout requires agreement but no school; failed saves keep form open',
    (tester) async {
      var calls = 0;
      await open(
        tester,
        children: 0,
        save: (_) async {
          calls++;
          throw Exception('Try again');
        },
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Continue to checkout'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      await agree(tester);
      await tester.tap(find.text('Continue to checkout'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('Could not save.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Back to cart'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'dialog fields, links, and validation stay readable over the real gradient theme',
    (tester) async {
      await open(tester, children: 1, save: (_) async {});
      await tester.tap(find.text('Continue to checkout'));
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(AlertDialog)));
      final background = theme.dialogTheme.backgroundColor!;
      for (final color in [
        theme.dialogTheme.contentTextStyle!.color!,
        theme.inputDecorationTheme.labelStyle!.color!,
        theme.inputDecorationTheme.floatingLabelStyle!.color!,
        theme.inputDecorationTheme.errorStyle!.color!,
        theme.listTileTheme.textColor!,
        theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
      ]) {
        final a = color.computeLuminance();
        final b = background.computeLuminance();
        expect(
          ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(find.text('Read the Exhibitor Handbook'), findsOneWidget);
      expect(find.text('Houston website and terms'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
