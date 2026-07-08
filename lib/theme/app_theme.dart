import 'package:flutter/material.dart';

class AppColors {
  static const pageBackground = Color(0xFF391C77);
  static const pageBackgroundMid = Color(0xFF4B2A8F);
  static const pageBackgroundDeep = Color(0xFF211044);
  static const header = Color(0xFF51A5AE);
  static const headerDark = Color(0xFF3F8F98);
  static const card = Color(0xFFE9EDEE);
  static const primaryButton = Color(0xFFF6C834);
  static const primaryButtonText = Color(0xFF1E2849);
  static const secondaryButton = Color(0xFF391C77);
  static const text = Color(0xFF1E2849);
  static const muted = Color(0xFF4D5566);
  static const headerText = Color(0xFF391C77);
  static const headerForeground = Colors.white;
  static const neutralBadgeBg = Color(0xFFE8EBEC);

  static const navy = text;
  static const navyDark = primaryButtonText;
  static const gold = primaryButton;
  static const bg = pageBackground;
  static const surface = card;
  static const accent = primaryButton;
  static const successBg = Color(0xFFEAF7EE);
  static const success = Color(0xFF1F7A3D);
  static const dangerBg = Color(0xFFFDECEC);
  static const danger = Color(0xFFB42318);
  static const warningBg = Color(0xFFFFF3CD);
  static const warningBorder = Color(0xFFE7C46A);
  static const warning = Color(0xFF7A4F00);
  static const infoBg = Color(0xFFEAF2FF);
  static const infoBorder = Color(0xFFB8D0FF);
}

class AppGradients {
  static const page = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.pageBackground,
      AppColors.pageBackgroundMid,
      AppColors.pageBackgroundDeep,
    ],
  );
}

class AppRadius {
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

class AppTheme {
  static Widget gradientTextScope(
    BuildContext context, {
    required Widget child,
  }) {
    return Theme(
      data: onGradientTheme(Theme.of(context)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.headerForeground),
        child: IconTheme(
          data: const IconThemeData(color: AppColors.headerForeground),
          child: child,
        ),
      ),
    );
  }

  static Widget surfaceTextScope(
    BuildContext context, {
    required Widget child,
  }) {
    return Theme(
      data: surfaceTheme(Theme.of(context)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.text),
        child: IconTheme(
          data: const IconThemeData(color: AppColors.text),
          child: child,
        ),
      ),
    );
  }

  static ThemeData onGradientTheme(ThemeData base) {
    final brightText = AppColors.headerForeground;
    final mutedText = AppColors.headerForeground.withValues(alpha: .82);

    return base.copyWith(
      textTheme: _textThemeWithColors(base.textTheme, brightText, mutedText),
      iconTheme: base.iconTheme.copyWith(color: brightText),
      listTileTheme: ListTileThemeData(
        textColor: brightText,
        iconColor: brightText,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          color: brightText,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: mutedText,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        textStyle: TextStyle(color: AppColors.text),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return mutedText.withValues(alpha: .45);
            }
            return brightText;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.disabled)
                ? mutedText.withValues(alpha: .28)
                : brightText.withValues(alpha: .9);
            return BorderSide(color: color, width: 1.4);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: brightText),
      ),
    );
  }

  static ThemeData surfaceTheme(ThemeData base) {
    return base.copyWith(
      textTheme: _textThemeWithColors(
        base.textTheme,
        AppColors.text,
        AppColors.muted,
      ),
      iconTheme: base.iconTheme.copyWith(color: AppColors.text),
      listTileTheme: ListTileThemeData(
        textColor: AppColors.text,
        iconColor: AppColors.text,
        titleTextStyle: base.textTheme.titleMedium?.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: AppColors.muted,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        textStyle: TextStyle(color: AppColors.text),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.secondaryButton),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.muted.withValues(alpha: .45);
            }
            return AppColors.secondaryButton;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.disabled)
                ? AppColors.muted.withValues(alpha: .28)
                : AppColors.secondaryButton;
            return BorderSide(color: color, width: 1.4);
          }),
        ),
      ),
    );
  }

  static TextTheme _textThemeWithColors(
    TextTheme textTheme,
    Color primary,
    Color muted,
  ) {
    return textTheme.copyWith(
      displayLarge: textTheme.displayLarge?.copyWith(color: primary),
      displayMedium: textTheme.displayMedium?.copyWith(color: primary),
      displaySmall: textTheme.displaySmall?.copyWith(color: primary),
      headlineLarge: textTheme.headlineLarge?.copyWith(color: primary),
      headlineMedium: textTheme.headlineMedium?.copyWith(color: primary),
      headlineSmall: textTheme.headlineSmall?.copyWith(color: primary),
      titleLarge: textTheme.titleLarge?.copyWith(color: primary),
      titleMedium: textTheme.titleMedium?.copyWith(color: primary),
      titleSmall: textTheme.titleSmall?.copyWith(color: primary),
      bodyLarge: textTheme.bodyLarge?.copyWith(color: primary),
      bodyMedium: textTheme.bodyMedium?.copyWith(color: primary),
      bodySmall: textTheme.bodySmall?.copyWith(color: muted),
      labelLarge: textTheme.labelLarge?.copyWith(color: primary),
      labelMedium: textTheme.labelMedium?.copyWith(color: primary),
      labelSmall: textTheme.labelSmall?.copyWith(color: muted),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.secondaryButton,
        brightness: Brightness.light,
        primary: AppColors.header,
        onPrimary: AppColors.headerText,
        secondary: AppColors.secondaryButton,
        onSecondary: AppColors.surface,
        tertiary: AppColors.primaryButton,
        onTertiary: AppColors.primaryButtonText,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(Colors.black),
        trackColor: WidgetStateProperty.all(
          Colors.black.withValues(alpha: .12),
        ),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(8),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.header,
        foregroundColor: AppColors.headerText,
        elevation: 0,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.pageBackground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          color: AppColors.headerForeground,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: AppColors.headerForeground.withValues(alpha: .9),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        margin: EdgeInsets.zero,
      ),
      textTheme: base.textTheme.copyWith(
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: AppColors.text,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: AppColors.text),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: AppColors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryButton,
          foregroundColor: AppColors.primaryButtonText,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondaryButton,
          side: const BorderSide(color: AppColors.secondaryButton, width: 1.4),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: AppColors.muted.withValues(alpha: .28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(
            color: AppColors.secondaryButton,
            width: 1.5,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.muted.withValues(alpha: .18),
        thickness: 1,
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}
