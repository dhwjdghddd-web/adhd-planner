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
  });

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

  factory Checkin.fromMap(Map<String, dynamic> map) => Checkin(
    dateKey: map['dateKey'] as String,
    mood: (map['mood'] as num).toInt(),
    energy: (map['energy'] as num).toInt(),
    note: map['note'] as String?,
  );
}
