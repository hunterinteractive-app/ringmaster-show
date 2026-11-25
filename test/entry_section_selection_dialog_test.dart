import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/entry_section_selection_dialog.dart';

void main() {
  testWidgets(
    'secretary bulk choice paints a light surface inside the purple sheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.onGradientTheme(ThemeData.light()),
          home: Builder(
            builder: (context) => Scaffold(
              backgroundColor: AppColors.pageBackground,
              body: buildAdminEntrySectionChoice(
                context,
                value: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final choice = find.byType(CheckboxListTile);
      final material = tester.widget<Material>(
        find.ancestor(of: choice, matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.surface);
      final theme = Theme.of(tester.element(choice));
      expect(theme.textTheme.bodyMedium!.color, AppColors.text);
      expect(tester.widget<CheckboxListTile>(choice).value, isTrue);
    },
  );
  Future<void> open(WidgetTester tester, String action) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(ThemeData.light()),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Theme(
                  data: AppTheme.surfaceDialogTheme(Theme.of(context)),
                  child: EntrySectionSelectionDialog(
                    action: action,
                    currentSectionId: 'a',
                    sections: const [
                      {'id': 'a', 'display_name': 'Open A', 'entry_count': 2},
                      {'id': 'b', 'display_name': 'Open B', 'entry_count': 2},
                      {'id': 'c', 'display_name': 'Open C', 'entry_count': 2},
                    ],
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
    'phone scratch starts with one section and requires explicit selection',
    (tester) async {
      await open(tester, 'Scratch');
      expect(find.text('Scratch 1 section'), findsOneWidget);
      await tester.tap(find.text('Select all sections'));
      await tester.pump();
      expect(find.text('Scratch 3 sections'), findsOneWidget);
      await tester.tap(find.text('Clear selection'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      final theme = Theme.of(
        tester.element(find.text('Scratch across sections')),
      );
      expect(theme.dialogTheme.backgroundColor, AppColors.surface);
      expect(theme.textTheme.bodyMedium!.color, AppColors.text);
    },
  );
  testWidgets('bulk editing always includes the entry being edited', (
    tester,
  ) async {
    await open(tester, 'Apply edits');
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Open A'),
          )
          .onChanged,
      isNull,
    );
    await tester.tap(find.text('Select all sections'));
    await tester.pump();
    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    expect(find.text('Apply edits 1 section'), findsOneWidget);
  });
}
