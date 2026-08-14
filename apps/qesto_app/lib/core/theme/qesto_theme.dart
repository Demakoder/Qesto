import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class QestoColors {
  static const background = Color(0xFFF6F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSecondary = Color(0xFFF0F3F8);
  static const primary = Color(0xFF3478F6);
  static const primarySoft = Color(0xFFEAF2FF);
  static const text = Color(0xFF171A22);
  static const secondaryText = Color(0xFF7B8190);
  static const border = Color(0xFFE9EBF0);
  static const green = Color(0xFF55C96F);
  static const orange = Color(0xFFFFB347);
  static const danger = Color(0xFFFF6B5F);
  static const purple = Color(0xFF8D63F6);
  static const positive = green;
  static const negative = danger;
  static const warning = orange;
  static const info = Color(0xFF5B8DEF);
}

@immutable
class QestoTypographyTokens extends ThemeExtension<QestoTypographyTokens> {
  const QestoTypographyTokens({
    required this.displayFamily,
    required this.uiFamily,
    required this.monoFamily,
  });

  final String? displayFamily;
  final String? uiFamily;
  final String? monoFamily;

  TextStyle display(TextStyle style, {bool numeric = false}) => style.copyWith(
    fontFamily: displayFamily,
    fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
  );

  TextStyle ui(TextStyle style, {bool numeric = false}) => style.copyWith(
    fontFamily: uiFamily,
    fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
  );

  TextStyle mono(TextStyle style) => style.copyWith(
    fontFamily: monoFamily,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  @override
  QestoTypographyTokens copyWith({
    String? displayFamily,
    String? uiFamily,
    String? monoFamily,
  }) => QestoTypographyTokens(
    displayFamily: displayFamily ?? this.displayFamily,
    uiFamily: uiFamily ?? this.uiFamily,
    monoFamily: monoFamily ?? this.monoFamily,
  );

  @override
  QestoTypographyTokens lerp(
    covariant QestoTypographyTokens? other,
    double t,
  ) => t < 0.5 || other == null ? this : other;
}

extension QestoTypographyContext on BuildContext {
  QestoTypographyTokens get qestoTypography =>
      Theme.of(this).extension<QestoTypographyTokens>()!;
}

ThemeData buildQestoTheme() {
  const displayFamily = 'IBM Plex Sans';
  const uiFamily = 'Manrope';
  const monoFamily = 'IBM Plex Mono';
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: QestoColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: QestoColors.primary,
      primary: QestoColors.primary,
      surface: QestoColors.surface,
      error: QestoColors.danger,
    ),
    fontFamily: uiFamily,
  );

  final uiTextTheme = base.textTheme.apply(fontFamily: uiFamily);
  TextStyle role(TextStyle? source, String? family) =>
      (source ?? const TextStyle()).copyWith(fontFamily: family);

  return base.copyWith(
    extensions: [
      QestoTypographyTokens(
        displayFamily: displayFamily,
        uiFamily: uiFamily,
        monoFamily: monoFamily,
      ),
    ],
    textTheme: uiTextTheme.copyWith(
      displayLarge: role(uiTextTheme.displayLarge, displayFamily),
      displayMedium: role(uiTextTheme.displayMedium, displayFamily),
      displaySmall: role(uiTextTheme.displaySmall, displayFamily),
      headlineLarge: role(uiTextTheme.headlineLarge, displayFamily),
      headlineMedium: role(uiTextTheme.headlineMedium, displayFamily),
      headlineSmall: role(
        const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: QestoColors.text,
          letterSpacing: -0.5,
        ),
        displayFamily,
      ),
      titleLarge: role(
        const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: QestoColors.text,
          letterSpacing: -0.3,
        ),
        displayFamily,
      ),
      titleMedium: role(
        const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: QestoColors.text,
        ),
        uiFamily,
      ),
      bodyLarge: role(
        const TextStyle(fontSize: 16, height: 1.35, color: QestoColors.text),
        uiFamily,
      ),
      bodyMedium: role(
        const TextStyle(fontSize: 14, height: 1.35, color: QestoColors.text),
        uiFamily,
      ),
      bodySmall: role(
        const TextStyle(
          fontSize: 12,
          height: 1.35,
          color: QestoColors.secondaryText,
        ),
        uiFamily,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: QestoColors.background,
      foregroundColor: QestoColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: QestoColors.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: QestoColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: QestoColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: QestoColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: QestoColors.primary, width: 1.5),
      ),
    ),
    splashFactory: InkRipple.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}
