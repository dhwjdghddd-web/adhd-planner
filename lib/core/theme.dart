import 'package:flutter/material.dart';

/// Theme + accessibility settings for the app. [fontScale] and
/// [reduceMotion] are driven by user settings and consumed via
/// [MediaQuery] overrides in `app.dart` so every screen respects them
/// without each widget reading settings individually.
class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  // Design Token Static Helpers for specific surfaces and semantic colors
  static Color surface1(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF171C23) : const Color(0xFFFFFFFF);
  static Color surface2(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E2630) : const Color(0xFFEEF1F5);
  static Color surface3(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF27303B) : const Color(0xFFFFFFFF);
  static Color surface4(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF323B47) : const Color(0xFFE6EBF1);
  static Color outlineColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A333D) : const Color(0xFFE4E9EF);
  static Color onHi(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE9EEF3) : const Color(0xFF171C22);
  static Color onMed(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68);
  static Color onLow(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF7E8995) : const Color(0xFF8A95A1);
  static Color success(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8FD0A6) : const Color(0xFF3F9D6A);
  static Color caution(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE6C480) : const Color(0xFF9C6F12);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = isDark
        ? const ColorScheme.dark(
            surface: Color(0xFF171C23),
            surfaceContainerHighest: Color(0xFF1E2630),
            primary: Color(0xFFA8CAFF),
            onPrimary: Color(0xFF06305F),
            primaryContainer: Color(0xFF284B73),
            onPrimaryContainer: Color(0xFFD8E7FF),
            secondaryContainer: Color(0xFF34404D),
            outline: Color(0xFF2A333D),
            onSurface: Color(0xFFE9EEF3),
            onSurfaceVariant: Color(0xFFA6B2BE),
            error: Color(0xFFE6C480),
            onError: Color(0xFF9C6F12),
          )
        : const ColorScheme.light(
            surface: Color(0xFFFFFFFF),
            surfaceContainerHighest: Color(0xFFEEF1F5),
            primary: Color(0xFF2C6FD6),
            onPrimary: Color(0xFFFFFFFF),
            primaryContainer: Color(0xFFD8E5FF),
            onPrimaryContainer: Color(0xFF0A2D5C),
            secondaryContainer: Color(0xFFE7EDF4),
            outline: Color(0xFFE4E9EF),
            onSurface: Color(0xFF171C22),
            onSurfaceVariant: Color(0xFF525C68),
            error: Color(0xFF9C6F12),
            onError: Color(0xFFFFFFFF),
          );

    final textTheme = TextTheme(
      displayLarge: const TextStyle(fontFamily: 'Pretendard', fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w700),
      displayMedium: const TextStyle(fontFamily: 'Pretendard', fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w700),
      displaySmall: const TextStyle(fontFamily: 'Pretendard', fontSize: 34, height: 40 / 34, fontWeight: FontWeight.w700),
      headlineLarge: const TextStyle(fontFamily: 'Pretendard', fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700),
      headlineMedium: const TextStyle(fontFamily: 'Pretendard', fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700),
      headlineSmall: const TextStyle(fontFamily: 'Pretendard', fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700),
      titleLarge: const TextStyle(fontFamily: 'Pretendard', fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600),
      titleMedium: const TextStyle(fontFamily: 'Pretendard', fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600),
      titleSmall: const TextStyle(fontFamily: 'Pretendard', fontSize: 17, height: 22 / 17, fontWeight: FontWeight.w600),
      bodyLarge: const TextStyle(fontFamily: 'Pretendard', fontSize: 15, height: 23 / 15, fontWeight: FontWeight.w400),
      bodyMedium: const TextStyle(fontFamily: 'Pretendard', fontSize: 15, height: 23 / 15, fontWeight: FontWeight.w400),
      bodySmall: const TextStyle(fontFamily: 'Pretendard', fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w400),
      labelLarge: const TextStyle(fontFamily: 'Pretendard', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600),
      labelMedium: const TextStyle(fontFamily: 'Pretendard', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
      labelSmall: const TextStyle(fontFamily: 'Pretendard', fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
    );

    final scaffoldBg = isDark ? const Color(0xFF0E1217) : const Color(0xFFF3F5F8);

    return ThemeData(
      colorScheme: scheme,
      textTheme: textTheme,
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.comfortable,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        // Must set the color explicitly: when titleTextStyle comes from the
        // theme, AppBar does NOT fold foregroundColor into it (it only does so
        // for its own default style), so a colorless headlineLarge left the
        // title an inherited near-white — fine on the dark scaffold, invisible
        // on the light one. onSurface tracks the brightness either way.
        titleTextStyle: textTheme.headlineLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF171C23) : const Color(0xFFFFFFFF),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFE4E9EF), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: isDark ? 0 : 3,
        hoverElevation: isDark ? 0 : 4,
        focusElevation: isDark ? 0 : 4,
        highlightElevation: isDark ? 0 : 4,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        sizeConstraints: const BoxConstraints.tightFor(width: 56, height: 56),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: const StadiumBorder(),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: textTheme.titleMedium,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.primary, width: 1),
          foregroundColor: scheme.primary,
          textStyle: textTheme.titleMedium,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF27303B) : const Color(0xFFFFFFFF),
        elevation: isDark ? 0 : 24,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF27303B) : const Color(0xFFFFFFFF),
        elevation: isDark ? 0 : 24,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        // floating으로 설정해야 SnackBar.margin이 적용된다.
        // 실제 margin 값은 app.dart의 showAppSnackBar 헬퍼에서 기기별
        // safe area를 더해 동적으로 설정한다.
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
