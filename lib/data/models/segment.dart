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

  /// True if [minute] falls inside this segment's range, accounting for
  /// midnight-wrapping ranges (e.g. 22:00~02:00 contains 23:30 and 01:00).
  bool containsMinute(int minute) {
    if (startMinute == endMinute) return false;
    final m = minute % TimeGeometry.minutesPerDay;
    if (startMinute < endMinute) {
      return m >= startMinute && m < endMinute;
    }
    return m >= startMinute || m < endMinute;
  }

  /// True if this segment's time range overlaps [other]'s, accounting for
  /// midnight-wrapping ranges. Shared by the segment editor's overlap
  /// warning and the dial painter's lane assignment for overlapping arcs.
  bool overlaps(Segment other) {
    for (final a in _intervals) {
      for (final b in other._intervals) {
        if (a.start < b.end && b.start < a.end) return true;
      }
    }
    return false;
  }

  /// Splits a (possibly midnight-wrapping) range into one or two
  /// non-wrapping half-open intervals for overlap comparison.
  List<_SegmentInterval> get _intervals {
    if (startMinute == endMinute) return const [];
    if (startMinute < endMinute) {
      return [_SegmentInterval(startMinute, endMinute)];
    }
    return [
      _SegmentInterval(startMinute, TimeGeometry.minutesPerDay),
      _SegmentInterval(0, endMinute),
    ];
  }

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

class _SegmentInterval {
  const _SegmentInterval(this.start, this.end);
  final int start;
  final int end;
}
