import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// One day's mood/energy check-in (T8) -- a short daily self-observation
/// ritual, not a medical record (this app makes no claim to clinical
/// accuracy; [mood]/[energy] are 1~5 self-ratings only). Keyed purely by
/// [dateKey] (one per day, saving again the same day overwrites it) --
/// unlike [Mit]/[AlarmSkip]/[Completion] this isn't tied to a block at all.
@immutable
class Checkin {
  final String dateKey;
  final int mood;
  final int energy;
  final String? note;

  const Checkin({
    required this.dateKey,
    required this.mood,
    required this.energy,
    this.note,
  }) : assert(mood >= 1 && mood <= 5, 'mood is a 1~5 self-rating'),
       assert(energy >= 1 && energy <= 5, 'energy is a 1~5 self-rating');

  /// Builds today's check-in (or [at]'s, for tests).
  factory Checkin.today({
    required int mood,
    required int energy,
    String? note,
    DateTime? at,
  }) {
    final n = at ?? DateTime.now();
    return Checkin(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      mood: mood,
      energy: energy,
      note: note,
    );
  }

  String get id => dateKey;

  Map<String, dynamic> toMap() => {
    'dateKey': dateKey,
    'mood': mood,
    'energy': energy,
    'note': note,
  };

  /// Defensive against malformed stored data: a missing/garbage rating falls
  /// back to 3 (neutral) and is clamped to 1~5, so one bad document can't crash
  /// the check-in stream or violate the constructor's invariant.
  factory Checkin.fromMap(Map<String, dynamic> map) => Checkin(
    dateKey: (map['dateKey'] as String?) ?? '',
    mood: _rating(map['mood']),
    energy: _rating(map['energy']),
    note: map['note'] as String?,
  );

  static int _rating(Object? value) =>
      (value is num ? value.toInt() : 3).clamp(1, 5);
}
