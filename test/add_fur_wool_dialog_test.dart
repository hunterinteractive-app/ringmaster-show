import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/services/ringmaster_backend.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/add_fur_wool_dialog.dart';

void main() {
  final fixture = <String, dynamic>{
    'tattoo': 'FUR1',
    'show_name': 'Holiday Show',
    'currency': 'USD',
    'sections': [
      {'id': 'a', 'label': 'Youth A', 'fee_cents': 200},
      {'id': 'b', 'label': 'Youth B', 'fee_cents': 300},
      {
        'id': 'c',
        'label': 'Youth C',
        'fee_cents': 200,
        'unavailable_reason': 'Already entered in Fur/Wool',
      },
      {
        'id': 'd',
        'label': 'Youth D',
        'fee_cents': 200,
        'unavailable_reason': 'Already in cart',
      },
    ],
  };
  Future<void> open(
    WidgetTester tester, {
    Future<Map<String, dynamic>> Function()? load,
    Future<Map<String, dynamic>> Function(List<String>, String)? save,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: AppColors.pageBackground,
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Theme(
                  data: AppTheme.surfaceDialogTheme(Theme.of(context)),
                  child: RepaintBoundary(
                    key: const Key('fur-preview'),
                    child: AddFurWoolDialog(
                      currentSectionId: 'a',
                      load: load ?? () async => fixture,
                      save:
                          save ??
                          (sections, variety) async => {'cart_id': 'cart'},
                    ),
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

  testWidgets(
    'phone picker selects sections, excludes duplicates, requires fur class and opens checkout once',
    (tester) async {
      List<String>? saved;
      String? savedVariety;
      final pending = Completer<Map<String, dynamic>>();
      await open(
        tester,
        save: (sections, variety) {
          saved = sections;
          savedVariety = variety;
          return pending.future;
        },
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Youth C'),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Youth D'),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Select all available sections'));
      await tester.pump();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Colored').last);
      await tester.pumpAndSettle();
      expect(find.text('Fur/Wool fees: USD 5.00'), findsOneWidget);
      final theme = Theme.of(tester.element(find.text('Add Fur/Wool')));
      expect(theme.dialogTheme.backgroundColor, AppColors.surface);
      expect(theme.textTheme.bodyMedium!.color, AppColors.text);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Continue to checkout'));
      await tester.pump();
      expect(saved, unorderedEquals(['a', 'b']));
      expect(savedVariety, 'Colored');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      pending.complete({'cart_id': 'cart'});
      await tester.pumpAndSettle();
      expect(find.text('Add Fur/Wool'), findsNothing);
    },
  );
  testWidgets('server rejection is visible and retry is possible on phone', (
    tester,
  ) async {
    await open(
      tester,
      load: () async => throw const PostgrestException(
        message: 'Fur/Wool can only be added while entries are open.',
      ),
    );
    expect(
      find.text('Fur/Wool can only be added while entries are open.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('no eligible sections does not offer checkout', (tester) async {
    await open(tester, load: () async => {...fixture, 'sections': []});
    expect(find.byType(FilledButton), findsNothing);
    expect(
      find.text('No eligible Fur/Wool sections are available for this rabbit.'),
      findsOneWidget,
    );
  });
  testWidgets('render phone dialog with production gradient parent', (
    tester,
  ) async {
    final font = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    await font.load();
    await open(tester);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('fur-preview')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '/tmp/add-fur-wool-phone.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  });
}
