import 'package:flutter/material.dart';

/// Theme + accessibility settings for the app. [fontScale] and
/// [reduceMotion] are driven by user settings (STEP 12) and consumed via
/// [MediaQuery] overrides in `app.dart` so every screen respects them
/// without each widget reading settings individually.
class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D8C),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Large, forgiving tap targets — important for users with attention
      // or motor-control variability under stress/distraction.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.comfortable,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(minimumSize: const Size(64, 56)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        sizeConstraints: BoxConstraints.tightFor(width: 64, height: 64),
      ),
    );
  }
}
