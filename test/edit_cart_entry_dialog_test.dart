import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/edit_cart_entry_dialog.dart';

void main() {
  const item = {
    'id': 'entry',
    'tattoo': 'TAG',
    'breed': 'Havana',
    'variety': 'Black',
    'species': 'rabbit',
    'sex': 'Buck',
    'class_name': 'Senior',
  };
  Future<void> open(
    WidgetTester t,
    Future<void> Function(Map<String, dynamic>) save, {
    Map<String, dynamic> entry = item,
  }) async {
    await t.pumpWidget(
      RepaintBoundary(
        key: const Key('preview'),
        child: MaterialApp(
          theme: AppTheme.onGradientTheme(ThemeData.light()),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => EditCartEntryDialog(
                    item: entry,
                    breeds: const [
                      {'name': 'Havana', 'class_system': 'four'},
                      {'name': 'Californian', 'class_system': 'six'},
                    ],
                    description: 'Family Exhibitor · Open A',
                    onSave: save,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'phone editor validates input, saves corrections only, and stays readable on purple theme',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final font = FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
      await font.load();
      Map<String, dynamic>? saved;
      await open(t, (v) async => saved = v);
      await t.enterText(
        find.widgetWithText(TextField, 'Tattoo / ear number'),
        '',
      );
      await t.tap(find.text('Save Changes'));
      await t.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Enter a tattoo / ear number.'), findsOneWidget);
      await t.enterText(
        find.widgetWithText(TextField, 'Tattoo / ear number'),
        'NEW42',
      );
      await t.enterText(find.widgetWithText(TextField, 'Variety'), 'Chocolate');
      expect(t.takeException(), isNull);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('preview')),
      );
      await t.runAsync(() async {
        final img = await boundary.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/cart-edit-phone.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      await t.tap(find.text('Save Changes'));
      await t.pumpAndSettle();
      expect(saved, {'tattoo': 'NEW42', 'variety': 'Chocolate'});
      expect(find.text('Edit Cart Entry'), findsNothing);
    },
  );
  testWidgets(
    'save failure preserves the values and allows correction; cancel does not save',
    (t) async {
      var calls = 0;
      await open(t, (v) async {
        calls++;
        throw StateError('Entry deadline passed');
      });
      await t.enterText(
        find.widgetWithText(TextField, 'Tattoo / ear number'),
        'KEEP',
      );
      await t.tap(find.text('Save Changes'));
      await t.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('Entry deadline passed'), findsOneWidget);
      expect(find.text('KEEP'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(calls, 1);
    },
  );
  testWidgets('meat pen edits keep the ID and class and accept three tattoos', (
    t,
  ) async {
    Map<String, dynamic>? saved;
    await open(
      t,
      (v) async => saved = v,
      entry: {
        ...item,
        'meat_pen_id': 'P001',
        'meat_pen_tattoos': ['A', 'B', 'C'],
        'class_name': 'Meat Pen',
      },
    );
    expect(find.widgetWithText(TextField, 'Tattoo / ear number'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, 'Tattoo 2'), 'NEW');
    await t.tap(find.text('Save Changes'));
    await t.pumpAndSettle();
    expect(saved, {
      'meat_pen_tattoos': ['A', 'NEW', 'C'],
    });
  });
}
