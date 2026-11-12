import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/edit_entry_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    String system = 'four',
    String species = 'rabbit',
    bool preJunior = false,
    String initial = 'Intermediate',
    bool missing = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.onGradientTheme(ThemeData.light()),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<EditEntryResult>(
                context: context,
                builder: (_) => EditEntryDialog(
                  initialAnimalId: 'a',
                  initialClassName: initial,
                  initialSectionId: 's',
                  initialExhibitorId: 'e',
                  breeds: missing
                      ? []
                      : [
                          {
                            'name': 'Belgian Hare (COD)',
                            'species': species,
                            'class_system': system,
                            'has_prejunior': preJunior,
                          },
                          {
                            'name': 'Californian',
                            'species': 'rabbit',
                            'class_system': 'six',
                          },
                        ],
                  animals: [
                    {
                      'id': 'a',
                      'breed': 'Belgian Hare',
                      'species': species,
                      'tattoo': 'MTB3',
                    },
                    {
                      'id': 'b',
                      'breed': 'Californian',
                      'species': 'rabbit',
                      'tattoo': 'OTHER',
                    },
                  ],
                  exhibitors: [
                    {'id': 'e', 'showing_name': 'Jackson Mossefin'},
                  ],
                  sections: [
                    {'id': 's'},
                  ],
                  sectionLabel: (_) => 'Open A',
                  onAddNewAnimal: () async {},
                  reloadAnimals: () async => [],
                ),
              ),
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }

  DropdownButtonFormField<String> field(WidgetTester tester) => tester.widget(
    find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String> &&
          w.key.toString().contains('class-'),
    ),
  );
  List<String> choices(WidgetTester tester) {
    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.key.toString().contains('class-'),
        ),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    return dropdown.items!.map((e) => e.value!).toList();
  }

  testWidgets(
    'four-class rejects previous Intermediate and saves Senior from dropdown',
    (tester) async {
      await open(tester);
      expect(find.byType(TextField), findsNothing);
      expect(choices(tester), ['Junior', 'Senior']);
      expect(field(tester).initialValue, isNull);
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Select a valid class for this breed.'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('class-a-Junior,Senior')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('class-a-Junior,Senior')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senior').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Entry'), findsNothing);
    },
  );
  testWidgets(
    'six-class and cavy retain Intermediate; prejunior is breed specific',
    (tester) async {
      await open(tester, system: 'six');
      expect(choices(tester), ['Junior', 'Intermediate', 'Senior']);
      expect(field(tester).initialValue, 'Intermediate');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await open(tester, species: 'cavy');
      expect(choices(tester), ['Junior', 'Intermediate', 'Senior']);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await open(tester, preJunior: true);
      expect(choices(tester), ['Pre-Junior', 'Junior', 'Senior']);
    },
  );
  testWidgets(
    'changing animals refreshes the class choices and clears invalid selection',
    (tester) async {
      await open(tester, initial: 'Senior');
      final animal = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Animal',
      );
      await tester.ensureVisible(animal);
      await tester.tap(animal);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('OTHER').last);
      await tester.pumpAndSettle();
      expect(choices(tester), ['Junior', 'Intermediate', 'Senior']);
      final classField = find.byKey(
        const ValueKey('class-b-Junior,Intermediate,Senior'),
      );
      await tester.ensureVisible(classField);
      await tester.pumpAndSettle();
      await tester.tap(classField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intermediate').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(animal);
      await tester.pumpAndSettle();
      await tester.tap(animal);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('MTB3').last);
      await tester.pumpAndSettle();
      expect(choices(tester), ['Junior', 'Senior']);
      expect(field(tester).initialValue, isNull);
    },
  );
  testWidgets(
    'unknown breed disables Save rather than allowing arbitrary classes',
    (tester) async {
      await open(tester, missing: true);
      expect(choices(tester), isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'phone dialog uses dark text on a light surface under purple parent',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester, initial: 'Senior');
      expect(tester.takeException(), isNull);
      final context = tester.element(find.text('Edit Entry'));
      final theme = Theme.of(context);
      expect(theme.textTheme.bodyMedium!.color, AppColors.text);
      expect(theme.dialogTheme.backgroundColor, AppColors.surface);
    },
  );
}
