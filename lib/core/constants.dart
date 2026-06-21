import 'package:flutter/material.dart';

/// Colour-blind-safe palette for day segments. Each colour is paired with an
/// icon and label everywhere it's shown, so colour is never the sole carrier
/// of meaning (core accessibility rule for this app).
const List<Color> kSegmentPalette = [
  Color(0xFF3E9A92), // teal
  Color(0xFFCE7752), // coral
  Color(0xFF8674B6), // lilac
  Color(0xFF579A60), // sage
  Color(0xFFA77E1E), // amber
  Color(0xFFBE6786), // rose
  Color(0xFF5483C0), // blue
  Color(0xFF717C89), // slate
];

/// Gets the theme-appropriate segment color based on the saved color.
/// Supports migrating old segment colors to the new 8-color palette dynamically.
Color getEffectiveSegmentColor(Color savedColor, Brightness brightness) {
  final value = savedColor.toARGB32();
  int index = -1;

  // Old palette values
  final oldValues = [
    0xFF2E7D8C,
    0xFFE07A5F,
    0xFF8E7DBE,
    0xFF3D9970,
    0xFFD4A017,
    0xFFC9576E,
    0xFF5B7DB1,
    0xFF6B6B6B,
  ];

  // New Dark values
  final darkValues = [
    0xFF7FC1BA, // teal
    0xFFE3A488, // coral
    0xFFB7A8D8, // lilac
    0xFF97C49C, // sage
    0xFFDBC084, // amber
    0xFFDAA3BB, // rose
    0xFF90B6DF, // blue
    0xFFAAB1BA, // slate
  ];

  // New Light values
  final lightValues = [
    0xFF3E9A92, // teal
    0xFFCE7752, // coral
    0xFF8674B6, // lilac
    0xFF579A60, // sage
    0xFFA77E1E, // amber
    0xFFBE6786, // rose
    0xFF5483C0, // blue
    0xFF717C89, // slate
  ];

  if (oldValues.contains(value)) {
    index = oldValues.indexOf(value);
  } else if (darkValues.contains(value)) {
    index = darkValues.indexOf(value);
  } else if (lightValues.contains(value)) {
    index = lightValues.indexOf(value);
  }

  if (index != -1) {
    return brightness == Brightness.dark
        ? Color(darkValues[index])
        : Color(lightValues[index]);
  }

  // Fallback to the saved color if it is a user custom color
  return savedColor;
}

/// Black or white, whichever stays legible *on* [background] — for an icon or
/// text drawn directly over a segment's colour. Segment colours are user-
/// picked and become light pastels in dark mode (see [getEffectiveSegmentColor]),
/// so a hardcoded white glyph washes out on them; this picks by luminance
/// instead. Mirrors `ThemeData.estimateBrightnessForColor`'s 0.5 threshold.
Color onSegmentColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

const double kMinTapTarget = 48.0;

/// Repeat-day encoding shared by routines: 1=Mon .. 7=Sun (ISO-8601 weekday).
const List<String> kWeekdayShortLabels = ['월', '화', '수', '목', '금', '토', '일'];
