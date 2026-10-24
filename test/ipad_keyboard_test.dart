import 'dart:convert';
import 'package:ringmaster_show/widgets/help_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/animal_editor/animal_editor_dialog.dart';
import 'package:ringmaster_show/widgets/exhibitor_builder_dialog.dart';

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void visibleAboveKeyboard(WidgetTester tester, Finder finder, double bottom) {
  final rect = tester.getRect(finder);
  expect(
    rect.top,
    greaterThanOrEqualTo(0),
    reason: '$finder is above the viewport',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(bottom),
    reason: '$finder is under the keyboard',
  );
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open form'));
  await settleKeyboard(tester);
}

Future<void> settleKeyboard(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> initializeFixtures() async {
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://ipad-fixture.invalid',
    anonKey: 'test',
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
      detectSessionInUri: false,
      localStorage: EmptyLocalStorage(),
    ),
    httpClient: MockClient((request) async {
      if (request.method != 'GET') {
        throw StateError('No writes allowed in keyboard tests');
      }
      final path = request.url.path;
      final rows = path.endsWith('/breeds')
          ? [
              {
                'id': 'tan',
                'name': 'Tan',
                'species': 'rabbit',
                'is_active': true,
              },
            ]
          : path.endsWith('/varieties')
          ? [
              {'id': 'black', 'name': 'Black'},
              {'id': 'blue', 'name': 'Blue'},
              {'id': 'chocolate', 'name': 'Chocolate'},
            ]
          : [];
      return http.Response(
        jsonEncode(rows),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  setUpAll(initializeFixtures);
  tearDownAll(() => Supabase.instance.dispose());

  for (final scenario in [
    (name: 'iPad portrait', size: const Size(768, 1024), keyboard: 360.0),
    (name: 'iPad landscape', size: const Size(1024, 768), keyboard: 352.0),
    (name: 'iPad mini landscape', size: const Size(1133, 744), keyboard: 352.0),
    (name: 'iPad split view', size: const Size(507, 768), keyboard: 352.0),
  ]) {
    testWidgets('${scenario.name}: Add Animal with keyboard and suggestions', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.reset);
      await open(tester, const AnimalEditorDialog());
      final tattoo = field('Tattoo / ID (required)');
      await tester.ensureVisible(tattoo);
      await tester.tap(tattoo);
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        tattoo,
        scenario.size.height - scenario.keyboard,
      );
      await tester.enterText(tattoo, 'IPAD1');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        field('Breed (required)'),
        scenario.size.height - scenario.keyboard,
      );
      await tester.enterText(field('Breed (required)'), 'ta');
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        find.text('Tan'),
        scenario.size.height - scenario.keyboard,
      );
      await tester.tap(find.text('Tan'));
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        field('Variety (required)'),
        scenario.size.height - scenario.keyboard,
      );
      await tester.enterText(field('Variety (required)'), 'bl');
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        find.text('Black'),
        scenario.size.height - scenario.keyboard,
      );
      await tester.tap(find.text('Black'));
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        find.widgetWithText(FilledButton, 'Save'),
        scenario.size.height - scenario.keyboard,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await settleKeyboard(tester);
      expect(find.byType(AnimalEditorDialog), findsNothing);
    });

    testWidgets(
      '${scenario.name}: exhibitor contact fields and Save remain reachable',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.size;
        addTearDown(tester.view.reset);
        await open(tester, const ExhibitorBuilderDialog());
        final textFields = find.byType(TextField);
        expect(textFields, findsWidgets);
        final target = textFields.last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
        await settleKeyboard(tester);
        visibleAboveKeyboard(
          tester,
          target,
          scenario.size.height - scenario.keyboard,
        );
        visibleAboveKeyboard(
          tester,
          find.widgetWithText(FilledButton, 'Save Exhibitor'),
          scenario.size.height - scenario.keyboard,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('${scenario.name}: issue report stays usable with keyboard', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.reset);
      await open(
        tester,
        const HelpReportDialog(pageTitle: 'Test', pageRoute: '/test'),
      );
      final message = field('What is wrong?');
      await tester.tap(message);
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
      await settleKeyboard(tester);
      await tester.ensureVisible(message);
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        message,
        scenario.size.height - scenario.keyboard,
      );
      visibleAboveKeyboard(
        tester,
        find.text('Send Report'),
        scenario.size.height - scenario.keyboard,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Add Animal keeps focused variety visible through rotation and keyboard dismissal',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(768, 1024);
      addTearDown(tester.view.reset);
      await open(tester, const AnimalEditorDialog());
      final breed = field('Breed (required)');
      await tester.ensureVisible(breed);
      await tester.enterText(breed, 'ta');
      await settleKeyboard(tester);
      await tester.tap(find.text('Tan'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      await settleKeyboard(tester);
      final variety = field('Variety (required)');
      visibleAboveKeyboard(tester, variety, 664);
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.viewInsets = const FakeViewPadding(bottom: 352);
      await settleKeyboard(tester);
      visibleAboveKeyboard(tester, variety, 416);
      tester.view.viewInsets = const FakeViewPadding();
      await settleKeyboard(tester);
      visibleAboveKeyboard(tester, variety, 768);
      visibleAboveKeyboard(
        tester,
        find.widgetWithText(FilledButton, 'Save'),
        768,
      );
      // Close while a keyboard metrics change still has a reveal callback pending.
      tester.view.viewInsets = const FakeViewPadding(bottom: 352);
      await tester.tap(find.text('Cancel'));
      await settleKeyboard(tester);
      expect(find.byType(AnimalEditorDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
