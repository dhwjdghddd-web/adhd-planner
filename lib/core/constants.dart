import 'package:flutter/material.dart';

/// Colour-blind-safe palette for day segments. Each colour is paired with an
/// icon and label everywhere it's shown, so colour is never the sole carrier
/// of meaning (core accessibility rule for this app).
const List<Color> kSegmentPalette = [
  Color(0xFF2E7D8C), // teal
  Color(0xFFE07A5F), // terracotta
  Color(0xFF8E7DBE), // violet
  Color(0xFF3D9970), // green
  Color(0xFFD4A017), // amber
  Color(0xFFC9576E), // rose
  Color(0xFF5B7DB1), // blue
  Color(0xFF6B6B6B), // neutral grey (fallback)
];

const double kMinTapTarget = 48.0;

/// Repeat-day encoding shared by routines: 1=Mon .. 7=Sun (ISO-8601 weekday).
const List<String> kWeekdayShortLabels = ['월', '화', '수', '목', '금', '토', '일'];
