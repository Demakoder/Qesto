import 'package:flutter/material.dart';

/// One semantic palette shared by widgets and painters. Content/merchant colours
/// are intentionally not transformed when the user changes the application theme.
@immutable
class QestoSemanticColors extends ThemeExtension<QestoSemanticColors> {
  const QestoSemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.text,
    required this.secondaryText,
    required this.border,
    required this.primary,
    required this.primarySoft,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.controlHighlight,
    required this.controlMid,
    required this.controlLow,
    required this.controlEdge,
    required this.chartGrid,
  });
  static const light = QestoSemanticColors(
    background: Color(0xFFF7F8F8),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFF0F2F3),
    text: Color(0xFF111315),
    secondaryText: Color(0xFF6B7177),
    border: Color(0xFFD9DDE0),
    primary: Color(0xFF424A50),
    primarySoft: Color(0xFFF0F3F5),
    positive: Color(0xFF14824F),
    negative: Color(0xFFA3424F),
    warning: Color(0xFF876635),
    controlHighlight: Color(0xFFFFFFFF),
    controlMid: Color(0xFFF0F3F5),
    controlLow: Color(0xFFE0E5E9),
    controlEdge: Color(0xFFC3C9CE),
    chartGrid: Color(0xFFE5E8EA),
  );
  static const dark = QestoSemanticColors(
    background: Color(0xFF1B1F22),
    surface: Color(0xFF242A2F),
    surfaceSecondary: Color(0xFF2D343A),
    text: Color(0xFFF1F0EC),
    secondaryText: Color(0xFFADB5BC),
    border: Color(0xFF444D55),
    primary: Color(0xFFCBD2D7),
    primarySoft: Color(0xFF343D45),
    positive: Color(0xFF6CD8A4),
    negative: Color(0xFFF09AA9),
    warning: Color(0xFFE1BF80),
    controlHighlight: Color(0xFF59646D),
    controlMid: Color(0xFF414B54),
    controlLow: Color(0xFF323A42),
    controlEdge: Color(0xFF68747F),
    chartGrid: Color(0xFF3A444C),
  );
  final Color background,
      surface,
      surfaceSecondary,
      text,
      secondaryText,
      border;
  final Color primary, primarySoft, positive, negative, warning;
  final Color controlHighlight, controlMid, controlLow, controlEdge, chartGrid;
  Color get workspace => background;
  Color get surfaceElevated => surfaceSecondary;
  Color get green => positive;
  Color get danger => negative;
  Color get orange => warning;
  Color get purple => secondaryText;
  Color get info => primary;
  Color get chartSurface => surface;
  Color get chartAxis => secondaryText;
  Color get chartTooltip => surfaceElevated;

  @override
  QestoSemanticColors copyWith() => this;
  @override
  QestoSemanticColors lerp(covariant QestoSemanticColors? other, double t) {
    if (other == null) return this;
    Color blend(Color a, Color b) => Color.lerp(a, b, t)!;
    return QestoSemanticColors(
      background: blend(background, other.background),
      surface: blend(surface, other.surface),
      surfaceSecondary: blend(surfaceSecondary, other.surfaceSecondary),
      text: blend(text, other.text),
      secondaryText: blend(secondaryText, other.secondaryText),
      border: blend(border, other.border),
      primary: blend(primary, other.primary),
      primarySoft: blend(primarySoft, other.primarySoft),
      positive: blend(positive, other.positive),
      negative: blend(negative, other.negative),
      warning: blend(warning, other.warning),
      controlHighlight: blend(controlHighlight, other.controlHighlight),
      controlMid: blend(controlMid, other.controlMid),
      controlLow: blend(controlLow, other.controlLow),
      controlEdge: blend(controlEdge, other.controlEdge),
      chartGrid: blend(chartGrid, other.chartGrid),
    );
  }
}

extension QestoSemanticContext on BuildContext {
  QestoSemanticColors get qestoColors =>
      Theme.of(this).extension<QestoSemanticColors>() ??
      QestoSemanticColors.light;
}
