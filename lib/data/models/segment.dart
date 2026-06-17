import 'package:flutter/material.dart';

import '../../core/time_geometry.dart';

/// A user-defined slice of the day (e.g. "오전", "퇴근 후") rendered as a
/// coloured arc on the circular dial. [startMinute]/[endMinute] are
/// minute-of-day (0~1440); a range that wraps past midnight is valid
/// (e.g. start=1320 end=120 means 22:00~02:00).
@immutable
class Segment {
  final String id;
  final String name;
  final int colorValue;
  final String iconKey;
  final int startMinute;
  final int endMinute;
  final int order;

  const Segment({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.startMinute,
    required this.endMinute,
    required this.order,
  });

  Color get color => Color(colorValue);

  int get lengthMinutes => TimeGeometry.lengthMinutes(startMinute, endMinute);

  Segment copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    int? startMinute,
    int? endMinute,
    int? order,
  }) {
    return Segment(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'order': order,
      };

  factory Segment.fromMap(Map<String, dynamic> map) => Segment(
        id: map['id'] as String,
        name: map['name'] as String,
        colorValue: map['colorValue'] as int,
        iconKey: map['iconKey'] as String,
        startMinute: map['startMinute'] as int,
        endMinute: map['endMinute'] as int,
        order: map['order'] as int,
      );
}
