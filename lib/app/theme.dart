import 'package:flutter/material.dart';

/// Colours from the SHA design (dark theme only for the MVP).
abstract final class ShaColors {
  static const background = Color(0xFF0E1316);
  static const surface = Color(0xFF192024);
  static const surfaceHigh = Color(0xFF232A2E);
  static const navBar = Color(0xFF151B1E);
  static const divider = Color(0xFF1C2327);
  static const outline = Color(0xFF3C4549);
  static const primary = Color(0xFF9DCBF7);
  static const onPrimary = Color(0xFF0A3150);
  static const primaryContainer = Color(0xFF1F4868);
  static const onPrimaryContainer = Color(0xFFD2E6FF);
  static const text = Color(0xFFE2E4E6);
  static const textSecondary = Color(0xFFBCC5CB);
  static const textMuted = Color(0xFF98A1A7);
  static const success = Color(0xFF86D6A0);
  static const onSuccess = Color(0xFF0D2B18);
  static const warning = Color(0xFFEFC27B);

  /// Destructive, irreversible actions only.
  static const danger = Color(0xFFF2B8B5);
  static const dangerContainer = Color(0xFF3B1A19);
  static const qrBackground = Color(0xFFF4F6F7);
  static const bubbleOutgoingText = Color(0xFFE6F0FC);
  static const bubbleOutgoingMeta = Color(0xFFA9C7E6);
  static const bubbleIncomingMeta = Color(0xFFA3ACB2);
}

abstract final class ShaFonts {
  static const sans = 'Manrope';
  static const mono = 'JetBrainsMono';
}

ThemeData buildShaTheme() {
  const scheme = ColorScheme.dark(
    surface: ShaColors.background,
    onSurface: ShaColors.text,
    onSurfaceVariant: ShaColors.textSecondary,
    surfaceContainerLow: ShaColors.navBar,
    surfaceContainer: ShaColors.surface,
    surfaceContainerHigh: ShaColors.surfaceHigh,
    primary: ShaColors.primary,
    onPrimary: ShaColors.onPrimary,
    primaryContainer: ShaColors.primaryContainer,
    onPrimaryContainer: ShaColors.onPrimaryContainer,
    secondaryContainer: ShaColors.primaryContainer,
    onSecondaryContainer: ShaColors.onPrimaryContainer,
    outline: ShaColors.outline,
    outlineVariant: ShaColors.divider,
    error: ShaColors.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: ShaFonts.sans,
    scaffoldBackgroundColor: ShaColors.background,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: ShaColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: ShaFonts.sans,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: ShaColors.text,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ShaColors.navBar,
      indicatorColor: ShaColors.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontFamily: ShaFonts.sans,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? ShaColors.text
              : ShaColors.textSecondary,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? ShaColors.onPrimaryContainer
              : ShaColors.textSecondary,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
          fontFamily: ShaFonts.sans,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
        foregroundColor: ShaColors.text,
        side: const BorderSide(color: Color(0xFF889197)),
        textStyle: const TextStyle(
          fontFamily: ShaFonts.sans,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: ShaColors.textMuted),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
