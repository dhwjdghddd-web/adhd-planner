import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A mood/energy check-in record (T8) -- a short daily/time-of-day self-observation
/// ritual, not a medical record (this app makes no claim to clinical
/// accuracy; [mood]/[energy] are 1~5 self-ratings only). Supports multiple
/// entries per day via unique [id], grouped by [dateKey] (yyyy-MM-dd), and
/// ordered by [createdAtIso].
@immutable
class Checkin {
  final String id;
  final String dateKey;
  final int mood;
  final int energy;
  final String? note;
  final String createdAtIso;

  Checkin({
    String? id,
    required this.dateKey,
    required this.mood,
    required this.energy,
    this.note,
    String? createdAtIso,
  })  : id = id ?? _uuid.v4(),
        createdAtIso = createdAtIso ?? DateTime.now().toIso8601String(),
        assert(mood >= 1 && mood <= 5, 'mood is a 1~5 self-rating'),
        assert(energy >= 1 && energy <= 5, 'energy is a 1~5 self-rating');

  /// Builds a check-in for today (or [at]'s, for tests/specified time).
  factory Checkin.today({
    String? id,
    required int mood,
    required int energy,
    String? note,
    DateTime? at,
  }) {
    final n = at ?? DateTime.now();
    return Checkin(
      id: id,
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      mood: mood,
      energy: energy,
      note: note,
      createdAtIso: n.toIso8601String(),
    );
  }

  DateTime get createdAt {
    try {
      return DateTime.parse(createdAtIso);
    } catch (_) {
      try {
        return DateTime.parse('${dateKey}T12:00:00');
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'dateKey': dateKey,
    'mood': mood,
    'energy': energy,
    'note': note,
    'createdAtIso': createdAtIso,
  };

  /// Defensive against malformed or legacy stored data:
  /// - Missing id falls back to dateKey or a new UUID.
  /// - Missing createdAtIso falls back to dateKey noon.
  /// - Missing/garbage rating falls back to 3 (neutral) and is clamped to 1~5.
  factory Checkin.fromMap(Map<String, dynamic> map) {
    final dateKey = (map['dateKey'] as String?) ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    final id = (map['id'] as String?) ?? (dateKey.isNotEmpty ? dateKey : _uuid.v4());
    final createdAtIso = (map['createdAtIso'] as String?) ?? (dateKey.isNotEmpty ? '${dateKey}T12:00:00.000Z' : DateTime.now().toIso8601String());

    return Checkin(
      id: id,
      dateKey: dateKey,
      mood: _rating(map['mood']),
      energy: _rating(map['energy']),
      note: map['note'] as String?,
      createdAtIso: createdAtIso,
    );
  }

  Checkin copyWith({
    String? id,
    String? dateKey,
    int? mood,
    int? energy,
    String? note,
    String? createdAtIso,
  }) {
    return Checkin(
      id: id ?? this.id,
      dateKey: dateKey ?? this.dateKey,
      mood: mood ?? this.mood,
      energy: energy ?? this.energy,
      note: note ?? this.note,
      createdAtIso: createdAtIso ?? this.createdAtIso,
    );
  }

  static int _rating(Object? value) =>
      (value is num ? value.toInt() : 3).clamp(1, 5);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Checkin &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          dateKey == other.dateKey &&
          mood == other.mood &&
          energy == other.energy &&
          note == other.note &&
          createdAtIso == other.createdAtIso;

  @override
  int get hashCode => Object.hash(id, dateKey, mood, energy, note, createdAtIso);
}
