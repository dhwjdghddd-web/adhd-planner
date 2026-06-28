import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/features/rewards/completion_celebration.dart';

void main() {
  Widget wrap({required bool reduceMotion, required int streakDays}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCompletionCelebration(
                context,
                reduceMotion: reduceMotion,
                streakDays: streakDays,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a non-milestone streak shows the plain completion message only',
      (tester) async {
    await tester.pumpWidget(wrap(reduceMotion: true, streakDays: 1));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsOneWidget);
    expect(find.textContaining('일 연속'), findsNothing);
  });

  testWidgets('a milestone streak (e.g. 7 days) adds a special streak line',
      (tester) async {
    await tester.pumpWidget(wrap(reduceMotion: true, streakDays: 7));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsOneWidget);
    expect(find.text('7일 연속, 정말 멋져요!'), findsOneWidget);
  });

  test('celebrationMilestones contains the documented milestone days', () {
    expect(celebrationMilestones, {3, 7, 14, 30, 60, 100});
  });

  testWidgets('reduceMotion swaps the confetti for a static icon without crashing',
      (tester) async {
    await tester.pumpWidget(wrap(reduceMotion: true, streakDays: 3));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.celebration), findsOneWidget);
    expect(find.text('3일 연속, 정말 멋져요!'), findsOneWidget);

    // Dismiss by tapping the barrier/body.
    await tester.tap(find.text('오늘 할 일을 다 끝냈어요!'));
    await tester.pumpAndSettle();
    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsNothing);
  });
}
