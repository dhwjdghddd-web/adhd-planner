import 'package:flutter/material.dart';

/// Fixed icon choices for segments. Icons always accompany colour so
/// colour-blind users can still tell segments apart (see core/constants.dart).
const Map<String, IconData> kSegmentIcons = {
  'wb_sunny': Icons.wb_sunny,
  'wb_twilight': Icons.wb_twilight,
  'nights_stay': Icons.nights_stay,
  'work': Icons.work,
  'home': Icons.home,
  'school': Icons.school,
  'fitness_center': Icons.fitness_center,
  'restaurant': Icons.restaurant,
  'coffee': Icons.coffee,
  'directions_walk': Icons.directions_walk,
  'bedtime': Icons.bedtime,
  'event': Icons.event,
};

IconData iconForKey(String key) => kSegmentIcons[key] ?? Icons.circle;
