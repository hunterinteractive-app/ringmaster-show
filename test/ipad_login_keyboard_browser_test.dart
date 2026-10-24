@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_show/screens/login_screen.dart';
import 'package:ringmaster_show/theme/app_theme.dart';
import 'ipad_keyboard_test.dart'
    show initializeFixtures, field, settleKeyboard, visibleAboveKeyboard;

void main() {
  setUpAll(initializeFixtures);
  tearDownAll(() => Supabase.instance.dispose());
  for (final scenario in [
    (name: 'iPad portrait', size: const Size(768, 1024), keyboard: 360.0),
    (name: 'iPad landscape', size: const Size(1024, 768), keyboard: 352.0),
    (name: 'iPad mini landscape', size: const Size(1133, 744), keyboard: 352.0),
    (name: 'iPad split view', size: const Size(507, 768), keyboard: 352.0),
  ]) {
    testWidgets('${scenario.name}: login email remains usable with keyboard', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme, home: const LoginScreen()),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await settleKeyboard(tester);
      final email = field('Email address');
      await tester.ensureVisible(email);
      await tester.tap(email);
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        email,
        scenario.size.height - scenario.keyboard,
      );
      await tester.enterText(email, 'keyboard-test@example.invalid');
      await tester.ensureVisible(find.text('Send login code'));
      await settleKeyboard(tester);
      visibleAboveKeyboard(
        tester,
        find.text('Send login code'),
        scenario.size.height - scenario.keyboard,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
