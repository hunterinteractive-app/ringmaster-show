import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/no_email_exhibitor_option.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  for (final enabled in [true, false]) {
    testWidgets('no-email row stays readable on purple, enabled=$enabled', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var value = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
          home: Scaffold(
            body: DecoratedBox(
              decoration: const BoxDecoration(gradient: AppGradients.page),
              child: Builder(
                builder: (context) => AppTheme.surfaceTextScope(
                  context,
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.3)),
                    child: StatefulBuilder(
                      builder: (context, setState) => Column(
                        children: [
                          NoEmailExhibitorOption(
                            value: value,
                            onChanged: enabled
                                ? (v) => setState(() => value = v!)
                                : null,
                          ),
                          const TextField(
                            decoration: InputDecoration(labelText: 'Email'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        find.text('No email address'),
        find.textContaining('Reports will need to be printed'),
      ]) {
        final textStyle = DefaultTextStyle.of(tester.element(label)).style;
        for (final background in AppGradients.page.colors) {
          final color = Color.alphaBlend(textStyle.color!, background);
          expect(contrast(color, background), greaterThanOrEqualTo(4.5));
        }
      }
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      for (final background in AppGradients.page.colors) {
        expect(
          contrast(checkbox.side!.color, background),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        contrast(
          checkbox.checkColor!,
          checkbox.fillColor!.resolve({WidgetState.selected})!,
        ),
        greaterThanOrEqualTo(3),
      );
      expect(
        Theme.of(
          tester.element(find.byType(TextField)),
        ).textTheme.bodyLarge!.color,
        AppColors.text,
      );
      await tester.tap(find.text('No email address'));
      await tester.pumpAndSettle();
      expect(value, enabled);
      expect(tester.takeException(), isNull);
    });
  }
}
