import '../../data/models/memo.dart';

/// How old an unreviewed memo must be before it's worth nudging about --
/// a fresh memo is still in the normal triage flow and doesn't need one.
const Duration kMemoNudgeMinAge = Duration(days: 3);

/// The single oldest unreviewed memo that's at least [kMemoNudgeMinAge] old
/// as of [now], or null if none qualify. Picks one memo (not a count) since
/// the nudge is meant to be a single occasional card, not a list. Pure (takes
/// "now" as a parameter) so it's testable without a real clock.
Memo? oldestNudgeworthyMemo(List<Memo> memos, DateTime now) {
  final candidates =
      memos.where((m) => !m.reviewed && now.difference(m.createdAt) >= kMemoNudgeMinAge);
  if (candidates.isEmpty) return null;
  return candidates.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
}
