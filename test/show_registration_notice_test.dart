import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'package:ringmaster_show/widgets/show_registration_notice.dart';

void main() {
  const note = 'Breed can be updated at check-in.';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Roboto')
      ..addFont(
        File(
          'assets/fonts/Roboto-Regular.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
  });

  Future<void> render(WidgetTester tester, String showId) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        // RingMasterPageShell wraps registration in this gradient theme.
        theme: AppTheme.onGradientTheme(AppTheme.lightTheme),
        home: Scaffold(
          backgroundColor: AppColors.pageBackground,
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [ShowRegistrationNotice(showId: showId)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final show in {
    'Open Breeding Rabbit': '232b7ed8-8032-4c05-aa87-db8e00de7dc2',
    'Youth Breeding Rabbit': '275bbfe9-6ef7-4c86-b914-23afee7ceffc',
  }.entries) {
    testWidgets('${show.key} notice wraps on a narrow phone', (tester) async {
      await render(tester, show.value);
      expect(find.text(note), findsOneWidget);
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text(note));
      final surface = tester.widget<Container>(
        find
            .ancestor(of: find.text(note), matching: find.byType(Container))
            .first,
      );
      final background = (surface.decoration! as BoxDecoration).color!;
      final foreground = text.style!.color!;
      expect(
        (background.computeLuminance() + .05) /
            (foreground.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.getRect(find.text(note)).right, lessThanOrEqualTo(320));
    });
  }

  for (final show in {
    'Cavy': '62c1a1ea-da4d-4ac5-a23e-065d14dce251',
    'Youth Meat Pen': '373e7ed1-5528-401d-90ed-8d9a12881d78',
    'Other show': 'unrelated-show',
  }.entries) {
    testWidgets('${show.key} has no breed update notice', (tester) async {
      await render(tester, show.value);
      expect(find.text(note), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });
  }
}
