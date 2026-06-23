import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/rewards/daily_checklist_badge.dart';

import '../../fakes/fake_planner_repository.dart';

Segment _block(String id, List<String> microSteps) {
  return Segment(
    id: id,
    name: id,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: 0,
    endMinute: 60,
    order: 0,
    microSteps: microSteps,
  );
}

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: DailyChecklistBadge())),
    );
  }

  testWidgets('shows a plain label when a block has no items', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block('s1', const []));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // No counts to show, but the badge still has to stay tappable as the entry
    // point into the full today-checklist screen.
    expect(find.text('오늘 체크리스트'), findsOneWidget);
  });

  testWidgets('shows nothing when no block exists at all', (tester) async {
    final repo = FakePlannerRepository();

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('체크리스트'), findsNothing);
  });

  testWidgets('sums items across every block', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block('s1', const ['a', 'b']));
    await repo.upsertSegment(_block('s2', const ['c', 'd', 'e']));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0]));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 체크리스트 1/5'), findsOneWidget);
  });

  testWidgets("excludes yesterday's checked progress from today's count", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block('s1', const ['a', 'b']));
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0], at: yesterday));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 체크리스트 0/2'), findsOneWidget);
  });

  testWidgets('switches to the streak flame icon once half of today is checked',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block('s1', const ['a', 'b']));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.checklist_rtl);

    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0]));
    await tester.pumpAndSettle();

    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.local_fire_department);
  });
}
