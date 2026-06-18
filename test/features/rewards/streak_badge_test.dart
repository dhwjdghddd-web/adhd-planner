import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
    await repo.setCompletion(Completion.now('r1', at: now));
    await repo.setCompletion(Completion.now('r1', at: now.subtract(const Duration(days: 1))));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('최고 2일'), findsOneWidget);
    expect(find.text('· 현재 2일'), findsOneWidget);
  });
}
