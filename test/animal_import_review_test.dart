import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/widgets/animal_import_review_panel.dart';

void main() {
  for (final provider in ['ringmaster_breeder', 'herdmaster', 'pedigreehq']) {
    for (final decision in ['link', 'separate', 'later']) {
      testWidgets(
        '$provider $decision confirms once and saves the selected identity',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var resolved = false;
          final writes = <Map<String, dynamic>>[];
          var reloads = 0;
          final animal = {
            'name': 'Dutch Doe',
            'tattoo': 'TEST',
            'species': 'rabbit',
            'breed': 'Dutch',
            'sex': 'Doe',
            'dob': null,
          };
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AnimalImportReviewPanel(
                    ownerId: 'owner',
                    onResolved: () async {
                      reloads++;
                    },
                    call: (args) async {
                      if (args['p_action'] == 'list') {
                        return resolved
                            ? []
                            : [
                                {
                                  'id': 'review',
                                  'provider': provider,
                                  'payload': animal,
                                  'updated_at': 'version',
                                  'candidates': [
                                    {
                                      'ringmaster_animal_id':
                                          'existing-show-id',
                                      'can_link': true,
                                      ...animal,
                                    },
                                  ],
                                },
                              ];
                      }
                      writes.add(args);
                      resolved = true;
                      return {'resolved': true};
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Is this the same animal?'), findsOneWidget);
          if (decision == 'link') {
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Use this animal'),
                  )
                  .onPressed,
              isNull,
            );
            await tester.tap(find.byType(CheckboxListTile));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Use this animal'));
          } else {
            await tester.tap(
              find.text(
                decision == 'separate'
                    ? 'Create a separate animal'
                    : 'Decide later',
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (decision == 'later') {
            expect(writes, isEmpty);
            expect(reloads, 0);
            expect(find.text('Review match'), findsOneWidget);
          } else {
            expect(writes.single['p_action'], decision);
            expect(
              writes.single['p_target'],
              decision == 'link' ? 'existing-show-id' : null,
            );
            expect(writes.single['p_version'], 'version');
            expect(reloads, 1);
            expect(find.text('Is this the same animal?'), findsNothing);
          }
        },
      );
    }
  }
}
