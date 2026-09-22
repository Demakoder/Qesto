import 'package:flutter/material.dart';
import '../../design_system/qesto_theme_data.dart';
export '../../design_system/qesto_tokens.dart';
export '../../design_system/qesto_semantic_colors.dart';

abstract final class QestoColors {
  static const background = Color(0xFFF7F8F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSecondary = Color(0xFFF0F2F3);
  static const primary = Color(0xFF424A50);
  static const primarySoft = Color(0xFFF0F3F5);
  static const text = Color(0xFF111315);
  static const secondaryText = Color(0xFF6B7177);
  static const border = Color(0xFFD9DDE0);
  static const green = Color(0xFF168B55);
  static const orange = Color(0xFF876635);
  static const danger = Color(0xFFA3424F);
  static const purple = Color(0xFF737E85);
  static const positive = green;
  static const negative = danger;
  static const warning = orange;
  static const info = Color(0xFF424A50);
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
    fontFamily: numeric ? 'Noto Serif Display' : displayFamily,
    fontFamilyFallback: const ['Onest'],
    fontStyle: numeric ? FontStyle.italic : FontStyle.normal,
    fontWeight: FontWeight.w400,
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

ThemeData buildQestoTheme({Brightness brightness = Brightness.light}) =>
    buildWhiteSilverTheme(
      brightness: brightness,
      typography: const QestoTypographyTokens(
        displayFamily: 'Prata',
        uiFamily: 'Onest',
        monoFamily: 'IBM Plex Mono',
      ),
    );
