import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_show/theme/app_theme.dart';

void main() {
  double contrastRatio(Color foreground, Color background) {
    final lighter =
        foreground.computeLuminance() > background.computeLuminance()
        ? foreground
        : background;
    final darker = identical(lighter, foreground) ? background : foreground;
    return (lighter.computeLuminance() + 0.05) /
        (darker.computeLuminance() + 0.05);
  }

  void expectAaTextContrast(
    String description,
    Color foreground,
    Color background,
  ) {
    expect(
      contrastRatio(foreground, background),
      greaterThanOrEqualTo(4.5),
      reason: '$description must meet WCAG AA normal-text contrast.',
    );
  }

  test('shared palette meets AA normal-text contrast requirements', () {
    expectAaTextContrast('Header text', AppColors.headerText, AppColors.header);
    expectAaTextContrast('Surface text', AppColors.text, AppColors.surface);
    expectAaTextContrast(
      'Muted surface text',
      AppColors.muted,
      AppColors.surface,
    );
    expectAaTextContrast(
      'Gradient text',
      AppColors.headerForeground,
      AppColors.pageBackground,
    );
    expectAaTextContrast(
      'Primary button text',
      AppColors.primaryButtonText,
      AppColors.primaryButton,
    );
    expectAaTextContrast(
      'Success status text',
      AppColors.success,
      AppColors.successBg,
    );
    expectAaTextContrast(
      'Danger status text',
      AppColors.danger,
      AppColors.dangerBg,
    );
    expectAaTextContrast(
      'Warning status text',
      AppColors.warning,
      AppColors.warningBg,
    );
  });

  test('keyboard popup-menu focus color is clearly visible', () {
    final theme = AppTheme.menuFocusTheme(ThemeData.light());
    expect(theme.focusColor, isNot(Colors.transparent));
  });

  test('global keyboard focus styling is configured', () {
    final theme = AppTheme.lightTheme;

    expect(theme.focusColor.a, greaterThan(0));
    expect(theme.iconButtonTheme.style?.overlayColor, isNotNull);
    expect(theme.inputDecorationTheme.focusedBorder?.borderSide.width, 3);
  });
}
