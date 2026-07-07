import 'package:flutter/material.dart';

class AppColors {
  static const pageBackground = Color(0xFF391C77);
  static const pageBackgroundMid = Color(0xFF4B2A8F);
  static const pageBackgroundDeep = Color(0xFF211044);
  static const header = Color(0xFFE9EDEE);
  static const headerDark = Color(0xFFD8DEE0);
  static const card = Color(0xFFE9EDEE);
  static const primaryButton = Color(0xFFF6C834);
  static const primaryButtonText = Color(0xFF1E2849);
  static const secondaryButton = Color(0xFF391C77);
  static const text = Color(0xFF1E2849);
  static const muted = Color(0xFF4D5566);
  static const headerForeground = Colors.white;
  static const neutralBadgeBg = Color(0xFFE8EBEC);

  static const navy = header;
  static const navyDark = headerDark;
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
  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.secondaryButton,
        brightness: Brightness.light,
        primary: AppColors.header,
        onPrimary: AppColors.text,
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
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
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
