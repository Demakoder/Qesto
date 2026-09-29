import 'package:flutter/material.dart';

/// The approved White Silver palette. Financial colours retain their meaning.
abstract final class QestoPalette {
  static const background = Color(0xFFF4F5F6);
  static const workspace = Color(0xFFF7F8F8);
  static const surface = Color(0xFFFFFFFF);
  static const secondary = Color(0xFFF0F2F3);
  static const text = Color(0xFF111315);
  static const muted = Color(0xFF6B7177);
  static const border = Color(0xFFD9DDE0);
  static const silverLight = Color(0xFFF0F3F5);
  static const silverMid = Color(0xFFD8DDE1);
  static const silverDark = Color(0xFFAEB6BD);
  static const silverEdge = Color(0xFFC3C9CE);
  static const income = Color(0xFF168B55);
  static const expense = Color(0xFFA3424F);
  static const warning = Color(0xFF876635);
  static const instrument = Color(0xFF171B1E);
  static const instrumentText = Color(0xFFCBD0D3);
  static const instrumentGrid = Color(0xFF343A3F);
}

abstract final class QestoGeometry {
  static const radius = 6.0;
  static const window = BorderRadius.all(Radius.circular(radius));
  static const control = BorderRadius.all(Radius.circular(5));
  static const data = BorderRadius.all(Radius.circular(3));
  static const edge = BorderSide(color: QestoPalette.border);
  static const windowShadow = [
    BoxShadow(color: Color(0x08161B1F), blurRadius: 12, offset: Offset(0, 3)),
  ];
  static const focusShadow = [
    BoxShadow(color: Color(0x16161B1F), blurRadius: 18, offset: Offset(0, 6)),
  ];
}

abstract final class QestoSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const section = 32.0;
  static EdgeInsets workspace(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600
      ? const EdgeInsets.fromLTRB(16, 16, 16, 24)
      : const EdgeInsets.fromLTRB(28, 24, 28, 40);
}

abstract final class QestoMotion {
  static const fast = Duration(milliseconds: 170);
  static const normal = Duration(milliseconds: 220);
  static const expand = Duration(milliseconds: 300);
  static Duration effective(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

abstract final class QestoTypography {
  static const uiFamily = 'Onest';
  static const ui = TextStyle(fontFamily: 'Onest', fontSize: 14, height: 1.4);
  static const uiMedium = TextStyle(
    fontFamily: 'Onest',
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static const uiStrong = TextStyle(
    fontFamily: 'Onest',
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
  static const sectionTitle = TextStyle(
    fontFamily: 'Prata',
    fontFamilyFallback: ['Onest'],
    fontSize: 22,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );
  static const moneyHero = TextStyle(
    fontFamily: 'Noto Serif Display',
    fontFamilyFallback: ['Onest'],
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w400,
    fontSize: 60,
    height: 1.2,
    letterSpacing: -1.6,
  );
  static const moneyLarge = TextStyle(
    fontFamily: 'Noto Serif Display',
    fontFamilyFallback: ['Onest'],
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w400,
    fontSize: 34,
    height: 1.2,
    letterSpacing: -0.5,
  );
  static const percentageHero = moneyLarge;
  static const table = TextStyle(
    fontFamily: 'Onest',
    fontSize: 13,
    height: 1.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const caption = TextStyle(
    fontFamily: 'Onest',
    fontSize: 12,
    height: 1.4,
  );
  static const metadata = TextStyle(
    fontFamily: 'Onest',
    fontSize: 11,
    height: 1.4,
  );
}

@immutable
class QestoVisualTokens extends ThemeExtension<QestoVisualTokens> {
  const QestoVisualTokens({
    this.workspace = QestoPalette.workspace,
    this.chrome = QestoPalette.surface,
    this.chromeText = QestoPalette.text,
    this.chromeBorder = QestoPalette.border,
  });
  static const light = QestoVisualTokens();
  static const dark = QestoVisualTokens(
    workspace: Color(0xFF1B1F22),
    chrome: Color(0xFF23282C),
    chromeText: Color(0xFFF1F3F4),
    chromeBorder: Color(0xFF3D454B),
  );
  final Color workspace;
  final Color chrome;
  final Color chromeText;
  final Color chromeBorder;
  @override
  QestoVisualTokens copyWith({
    Color? workspace,
    Color? chrome,
    Color? chromeText,
    Color? chromeBorder,
  }) => QestoVisualTokens(
    workspace: workspace ?? this.workspace,
    chrome: chrome ?? this.chrome,
    chromeText: chromeText ?? this.chromeText,
    chromeBorder: chromeBorder ?? this.chromeBorder,
  );
  @override
  QestoVisualTokens lerp(covariant QestoVisualTokens? other, double t) =>
      other == null
      ? this
      : QestoVisualTokens(
          workspace: Color.lerp(workspace, other.workspace, t)!,
          chrome: Color.lerp(chrome, other.chrome, t)!,
          chromeText: Color.lerp(chromeText, other.chromeText, t)!,
          chromeBorder: Color.lerp(chromeBorder, other.chromeBorder, t)!,
        );
}

extension QestoVisualContext on BuildContext {
  QestoVisualTokens get qestoVisual =>
      Theme.of(this).extension<QestoVisualTokens>() ?? QestoVisualTokens.light;
}
