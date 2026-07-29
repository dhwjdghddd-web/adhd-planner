import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Marks a whole calendar day as a deliberate **rest day**: all of that day's
/// alarms are suppressed and the home screen shows a calm rest mode, with the
/// streak protected (a rest day never counts as a miss). Keyed purely by
/// [dateKey] (presence = resting), the same per-day pattern as
/// [Mit]/[AlarmSkip], so a new day naturally starts un-rested.
///
/// The key is the *whole* model: "오늘은 쉬기" and "내일 쉬기" write the same
/// kind of record, just for a different day — which is why a mark set tonight
/// for tomorrow needs no migration at midnight, it simply starts matching
/// today's key instead (see isRestDayOn / isRestDayTomorrow).
@immutable
class RestDay {
  final String dateKey;

  const RestDay({required this.dateKey});

  /// Builds the rest mark for [at]'s calendar day (defaults to today).
  factory RestDay.today({DateTime? at}) {
    final n = at ?? DateTime.now();
    return RestDay(dateKey: DateFormat('yyyy-MM-dd').format(n));
  }

  String get id => dateKey;

  Map<String, dynamic> toMap() => {'dateKey': dateKey};

  factory RestDay.fromMap(Map<String, dynamic> map) =>
      RestDay(dateKey: (map['dateKey'] as String?) ?? '');
}
