import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Marks a whole calendar day as a deliberate **rest day** ("오늘은 쉬기"): all
/// of that day's alarms are suppressed and the home screen shows a calm rest
/// mode, with the streak protected (a rest day never counts as a miss). Keyed
/// purely by [dateKey] (presence = resting), the same per-day pattern as
/// [Mit]/[AlarmSkip], so a new day naturally starts un-rested.
@immutable
class RestDay {
  final String dateKey;

  const RestDay({required this.dateKey});

  /// Builds today's rest mark (or [at]'s, for tests).
  factory RestDay.today({DateTime? at}) {
    final n = at ?? DateTime.now();
    return RestDay(dateKey: DateFormat('yyyy-MM-dd').format(n));
  }

  String get id => dateKey;

  Map<String, dynamic> toMap() => {'dateKey': dateKey};

  factory RestDay.fromMap(Map<String, dynamic> map) =>
      RestDay(dateKey: (map['dateKey'] as String?) ?? '');
}
