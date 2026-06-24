import 'package:flutter/material.dart';

/// Colour-blind-safe palette for day segments. Each colour is paired with an
/// icon and label everywhere it's shown, so colour is never the sole carrier
/// of meaning (core accessibility rule for this app). Light-mode values (the
/// canonical, persisted ones) -- dark-mode display values live alongside in
/// [getEffectiveSegmentColor].
const List<Color> kSegmentPalette = [
  Color(0xFF1B948A), // teal
  Color(0xFFDB6128), // coral
  Color(0xFF7853C2), // lilac
  Color(0xFF3C9D4A), // sage
  Color(0xFFB17800), // amber
  Color(0xFFCB4279), // rose
  Color(0xFF2D6CCF), // blue
  Color(0xFF5C6874), // slate
];

/// Gets the theme-appropriate segment color based on the saved color.
/// Supports migrating segment colors saved under a past palette generation
/// forward to the current 8-color palette dynamically.
Color getEffectiveSegmentColor(Color savedColor, Brightness brightness) {
  final value = savedColor.toARGB32();
  int index = -1;

  // Past palette generations, oldest first. A saved colour may match any
  // past generation's light OR dark display value (whichever was actually
  // persisted at the time), so every generation is checked.
  final legacyGenerations = [
    // gen 0
    const [0xFF2E7D8C, 0xFFE07A5F, 0xFF8E7DBE, 0xFF3D9970, 0xFFD4A017, 0xFFC9576E, 0xFF5B7DB1, 0xFF6B6B6B],
    // gen 1 dark
    const [0xFF7FC1BA, 0xFFE3A488, 0xFFB7A8D8, 0xFF97C49C, 0xFFDBC084, 0xFFDAA3BB, 0xFF90B6DF, 0xFFAAB1BA],
    // gen 1 light
    const [0xFF3E9A92, 0xFFCE7752, 0xFF8674B6, 0xFF579A60, 0xFFA77E1E, 0xFFBE6786, 0xFF5483C0, 0xFF717C89],
  ];

  for (final gen in legacyGenerations) {
    if (gen.contains(value)) {
      index = gen.indexOf(value);
      break;
    }
  }

  // Current (gen 2) dark display values; light values are kSegmentPalette.
  const darkValues = [
    0xFF5BC6BA, // teal
    0xFFEF9A6B, // coral
    0xFFB690E2, // lilac
    0xFF79CC82, // sage
    0xFFE8C45C, // amber
    0xFFE78FB3, // rose
    0xFF6CADEC, // blue
    0xFFA3ADBB, // slate
  ];

  if (index == -1) {
    final lightValues = kSegmentPalette.map((c) => c.toARGB32()).toList();
    if (lightValues.contains(value)) index = lightValues.indexOf(value);
  }

  if (index != -1) {
    return brightness == Brightness.dark ? Color(darkValues[index]) : kSegmentPalette[index];
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
