import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A calendar day that has been recorded as "achieved" (see
/// `dailyAchievementFor`). Presence of a record *is* the fact — there is no
/// "achieved: false" record, because the whole point of persisting this is
/// that an earned day stays earned: streaks read these stored days instead of
/// recomputing every past day from the *current* routine list, so editing or
/// deleting a routine later can never retroactively take a day off someone's
/// streak.
///
/// Written once, never removed, keyed by [dateKey] ("yyyy-MM-dd" in local
/// time, same convention as [Completion]/[MicroStepProgress]).
@immutable
class AchievedDay {
  final String dateKey;

  const AchievedDay({required this.dateKey});

  factory AchievedDay.forDay(DateTime day) =>
      AchievedDay(dateKey: DateFormat('yyyy-MM-dd').format(day));

  String get id => dateKey;

  Map<String, dynamic> toMap() => {'dateKey': dateKey};

  factory AchievedDay.fromMap(Map<String, dynamic> map) =>
      AchievedDay(dateKey: map['dateKey'] as String);
}
