import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/screens/admin/admin_entry_management_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<Map<String, dynamic>> Function() loader,
  ) async {
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
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                backgroundColor: Colors.transparent,
                builder: (_) => buildAdminExhibitorSheet(
                  context,
                  exhibitor: const {
                    'id': 'kid',
                    'showing_name': 'Youth Exhibitor',
                  },
                  showId: 'show',
                  schoolInformationLoader: loader,
                ),
              ),
              child: const Text('View'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
  }

  final data = <String, dynamic>{
    'applicable': true,
    'school': {
      'school_name': 'A Long School Name That Should Wrap On A Phone',
      'city': 'Houston',
      'state': 'TX',
    },
  };

  testWidgets(
    'View Exhibitor shows readable, read-only school details on phone',
    (tester) async {
      await open(tester, () async => data);
      expect(find.text('View Exhibitor'), findsOneWidget);
      for (final value in (data['school'] as Map).values) {
        final finder = find.text(value as String);
        await tester.ensureVisible(finder);
        expect(finder, findsOneWidget);
        final color = tester.widget<EditableText>(finder).style.color!;
        final luminance = color.computeLuminance();
        final surface = AppColors.surface.computeLuminance();
        expect((surface + .05) / (luminance + .05), greaterThanOrEqualTo(4.5));
      }
      expect(find.text('School name'), findsOneWidget);
      expect(find.text('School city'), findsOneWidget);
      expect(find.text('School state'), findsOneWidget);
      expect(find.text('Save Exhibitor'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary and Open-only exhibitors do not show a school section',
    (tester) async {
      await open(tester, () async => {'applicable': false});
      expect(find.text('School Information'), findsNothing);
      expect(find.text('Email'), findsOneWidget);
    },
  );

  testWidgets(
    'missing information is distinct from a retryable loading error',
    (tester) async {
      var calls = 0;
      await open(tester, () async {
        calls++;
        if (calls == 1) throw StateError('No permission or connection');
        return {'applicable': true, 'school': null};
      });
      expect(
        find.text('School information could not be loaded.'),
        findsOneWidget,
      );
      expect(find.textContaining('No permission'), findsNothing);
      await tester.ensureVisible(find.text('Retry'));
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(
        find.text('School information has not been provided for this show.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
