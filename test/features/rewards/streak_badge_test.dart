import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/rewards/streak_badge.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: StreakBadge())),
    );
  }

  testWidgets('shows an encouragement line instead of a bare 0 streak',
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('오늘 하나라도 했으면 충분해요'), findsOneWidget);
  });

  testWidgets('shows the best streak emphasized and the current streak softly',
      (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    // Yesterday was banked as achieved (what _AchievementRecorder persists);
    // today counts live off its own completion.
    await repo.saveAchievedDay(AchievedDay.forDay(now.subtract(const Duration(days: 1))));
    await repo.setCompletion(Completion.now('r1', at: now));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('최고 2일'), findsOneWidget);
    expect(find.text('· 현재 2일'), findsOneWidget);
  });

  testWidgets(
      'a streak that just dropped to 0 shows a gentle restart cue instead of a bare 0',
      (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    // Banked 10 days ago: far enough in the past that the gap exceeds the
    // freeze allowance, so longestStreak is 1 (best > 0) but currentStreak is
    // 0 -- exactly the "just dropped to 0" case that must not read as a bare
    // "0" or go silent.
    await repo.saveAchievedDay(AchievedDay.forDay(now.subtract(const Duration(days: 10))));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('최고 1일'), findsOneWidget);
    expect(find.text('· 다시 시작해도 좋아요'), findsOneWidget);
    // Never speaks the streak as a bare 0, in the accessible label either --
    // and positively offers the warm restart cue to screen readers.
    expect(find.bySemanticsLabel(RegExp(r'현재 연속 0일')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('최고 연속 1일, 다시 시작해도 좋아요')), findsOneWidget);
  });

  testWidgets('a banked past day keeps counting even after its routine is deleted',
      (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    // A routine existed and earned two days, both banked. Then the routine is
    // gone -- but the streak it built must survive, which is the whole reason
    // achieved days are stored rather than recomputed from current routines.
    // Both days are in the past (today is always recomputed live, so a banked
    // "today" wouldn't demonstrate the survival-of-history guarantee).
    await repo.saveAchievedDay(AchievedDay.forDay(now.subtract(const Duration(days: 1))));
    await repo.saveAchievedDay(AchievedDay.forDay(now.subtract(const Duration(days: 2))));
    // No routines, no completions, no progress at all.

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('최고 2일'), findsOneWidget);
  });
}
