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

  test(
    'surface form dialogs keep contrast from light and gradient parents',
    () {
      for (final parent in [
        AppTheme.lightTheme,
        AppTheme.onGradientTheme(AppTheme.lightTheme),
        AppTheme.surfaceTheme(AppTheme.lightTheme),
      ]) {
        final theme = AppTheme.surfaceDialogTheme(parent);
        final background = theme.dialogTheme.backgroundColor!;
        for (final foreground in [
          theme.dialogTheme.titleTextStyle!.color!,
          theme.dialogTheme.contentTextStyle!.color!,
          theme.listTileTheme.textColor!,
          theme.inputDecorationTheme.labelStyle!.color!,
          theme.inputDecorationTheme.floatingLabelStyle!.color!,
          theme.inputDecorationTheme.helperStyle!.color!,
          theme.inputDecorationTheme.errorStyle!.color!,
          theme.textButtonTheme.style!.foregroundColor!.resolve({})!,
        ]) {
          expectAaTextContrast(
            'Dialog labels, helpers, errors and actions',
            foreground,
            background,
          );
        }
      }
    },
  );

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
