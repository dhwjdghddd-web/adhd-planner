DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _key(DateTime d) => d.toIso8601String().split('T').first;

/// Consecutive-day streak ending today, over the set of "yyyy-MM-dd"
/// day-keys that have at least one completion (`Completion.dateKey`).
/// Non-punitive: up to [freezeAllowance] missed days are silently forgiven
/// without breaking the streak, so skipping a single day never drops a
/// user straight back to zero. If today has no completion yet, today isn't
/// counted as a miss — it isn't over — so the walk starts from yesterday
/// instead, preserving whatever streak was built through then.
int currentStreak(Set<String> completedDateKeys, {DateTime? today, int freezeAllowance = 2}) {
  var cursor = _dateOnly(today ?? DateTime.now());
  if (!completedDateKeys.contains(_key(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }

  var streak = 0;
  var freezesLeft = freezeAllowance;
  while (true) {
    if (completedDateKeys.contains(_key(cursor))) {
      streak++;
    } else if (freezesLeft > 0) {
      freezesLeft--;
    } else {
      break;
    }
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Longest streak ever achieved, applying a fresh [freezeAllowance] budget
/// to each run (a run ends once a gap exceeds the remaining freezes).
int longestStreak(Set<String> completedDateKeys, {int freezeAllowance = 2}) {
  if (completedDateKeys.isEmpty) return 0;
  final dates = completedDateKeys.map(DateTime.parse).toList()..sort();

  var best = 0;
  var run = 0;
  var freezesLeft = freezeAllowance;
  DateTime? previous;
  for (final date in dates) {
    if (previous == null) {
      run = 1;
      freezesLeft = freezeAllowance;
    } else {
      final missedDays = date.difference(previous).inDays - 1;
      if (missedDays <= freezesLeft) {
        freezesLeft -= missedDays;
        run += 1;
      } else {
        run = 1;
        freezesLeft = freezeAllowance;
      }
    }
    previous = date;
    if (run > best) best = run;
  }
  return best;
}
