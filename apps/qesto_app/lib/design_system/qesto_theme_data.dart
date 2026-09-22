import 'package:flutter/material.dart';
import 'qesto_silver.dart';
import 'qesto_tokens.dart';
import 'qesto_semantic_colors.dart';

ThemeData buildWhiteSilverTheme({
  required Brightness brightness,
  required ThemeExtension<dynamic> typography,
}) {
  final dark = brightness == Brightness.dark;
  final v = dark ? QestoVisualTokens.dark : QestoVisualTokens.light;
  final c = dark ? QestoSemanticColors.dark : QestoSemanticColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF424A50),
        brightness: brightness,
      ).copyWith(
        primary: c.primary,
        onPrimary: dark ? c.background : Colors.white,
        primaryContainer: dark ? const Color(0xFF3D454B) : c.primarySoft,
        onPrimaryContainer: v.chromeText,
        secondary: c.primary,
        secondaryContainer: dark ? const Color(0xFF3D454B) : c.surfaceSecondary,
        onSecondaryContainer: v.chromeText,
        surface: v.chrome,
        onSurface: v.chromeText,
        surfaceTint: Colors.transparent,
        outline: v.chromeBorder,
        outlineVariant: v.chromeBorder,
        error: dark ? const Color(0xFFE9A0AB) : c.negative,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Onest',
    scaffoldBackgroundColor: v.workspace,
  );
  final shape = RoundedRectangleBorder(borderRadius: QestoGeometry.control);
  final primary = ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.disabled) ? c.secondaryText : c.text,
    ),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(shape),
    minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    textStyle: const WidgetStatePropertyAll(QestoTypography.uiStrong),
    animationDuration: QestoMotion.fast,
    backgroundBuilder: QestoSilverSurface.buttonBackground,
  );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: QestoGeometry.control,
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    extensions: [v, c, typography],
    textTheme: base.textTheme.copyWith(
      displayLarge: QestoTypography.moneyHero.copyWith(color: v.chromeText),
      displayMedium: QestoTypography.moneyLarge.copyWith(color: v.chromeText),
      displaySmall: QestoTypography.moneyLarge.copyWith(
        fontSize: 28,
        color: v.chromeText,
      ),
      headlineLarge: QestoTypography.sectionTitle.copyWith(
        fontSize: 28,
        color: v.chromeText,
      ),
      headlineMedium: QestoTypography.sectionTitle.copyWith(
        fontSize: 24,
        color: v.chromeText,
      ),
      headlineSmall: QestoTypography.sectionTitle.copyWith(color: v.chromeText),
      titleLarge: QestoTypography.sectionTitle.copyWith(
        fontSize: 20,
        color: v.chromeText,
      ),
      titleMedium: QestoTypography.uiStrong.copyWith(
        fontSize: 15,
        color: v.chromeText,
      ),
      titleSmall: QestoTypography.uiStrong.copyWith(color: v.chromeText),
      bodyLarge: QestoTypography.ui.copyWith(fontSize: 16, color: v.chromeText),
      bodyMedium: QestoTypography.ui.copyWith(color: v.chromeText),
      bodySmall: QestoTypography.caption.copyWith(color: c.secondaryText),
      labelLarge: QestoTypography.uiStrong.copyWith(color: v.chromeText),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: v.chrome,
      foregroundColor: v.chromeText,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: QestoTypography.uiStrong.copyWith(
        fontSize: 18,
        color: v.chromeText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: primary),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primary),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: v.chromeText,
        side: BorderSide(color: v.chromeBorder),
        shape: shape,
        textStyle: QestoTypography.uiStrong,
        minimumSize: const Size(40, 40),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: v.chromeText,
        shape: shape,
        textStyle: QestoTypography.uiStrong,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: v.chromeText, shape: shape),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: v.chrome,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(v.chromeBorder),
      enabledBorder: border(v.chromeBorder),
      focusedBorder: border(c.primary, 1.5),
      errorBorder: border(scheme.error),
      focusedErrorBorder: border(scheme.error, 1.5),
      disabledBorder: border(v.chromeBorder),
      labelStyle: QestoTypography.caption.copyWith(color: c.secondaryText),
      hintStyle: QestoTypography.caption.copyWith(color: c.secondaryText),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: v.chrome,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: QestoGeometry.window,
        side: BorderSide(color: v.chromeBorder),
      ),
      titleTextStyle: QestoTypography.sectionTitle.copyWith(
        fontSize: 20,
        color: v.chromeText,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: v.chrome,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: v.chrome,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: QestoGeometry.control,
        side: BorderSide(color: v.chromeBorder),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      side: BorderSide(color: v.chromeBorder),
      backgroundColor: v.chrome,
      selectedColor: dark ? const Color(0xFF3D454B) : c.controlMid,
      labelStyle: QestoTypography.uiMedium.copyWith(color: v.chromeText),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(shape),
        textStyle: const WidgetStatePropertyAll(QestoTypography.uiMedium),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : v.chrome,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: v.chrome,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.controlMid,
      indicatorShape: shape,
      labelTextStyle: WidgetStatePropertyAll(
        QestoTypography.metadata.copyWith(color: v.chromeText),
      ),
      height: 68,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: v.chrome,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(scheme.secondaryContainer),
      headingTextStyle: QestoTypography.uiStrong.copyWith(color: v.chromeText),
      dataTextStyle: QestoTypography.table.copyWith(color: v.chromeText),
      dividerThickness: .7,
      headingRowHeight: 42,
      dataRowMinHeight: 48,
      dataRowMaxHeight: 72,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: v.chromeBorder,
      linearMinHeight: 4,
    ),
    dividerTheme: DividerThemeData(
      color: v.chromeBorder,
      thickness: .7,
      space: 1,
    ),
    dividerColor: v.chromeBorder,
    cardTheme: CardThemeData(
      color: v.chrome,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: QestoGeometry.window,
        side: BorderSide(color: v.chromeBorder),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.chartTooltip,
        borderRadius: QestoGeometry.data,
      ),
      textStyle: QestoTypography.caption.copyWith(color: c.text),
    ),
    splashFactory: InkRipple.splashFactory,
  );
}
