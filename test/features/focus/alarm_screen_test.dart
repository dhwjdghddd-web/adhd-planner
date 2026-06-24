import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/alarm_screen.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/memos/quick_add_button.dart';

import '../../fakes/fake_planner_repository.dart';

Segment _block({String id = 's1', String name = '약 먹기', int startMinute = 9 * 60 + 30}) {
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: startMinute + 60,
    order: 0,
  );
}

void main() {
  // AlarmScreen is pushed as a full-screen route over the existing Navigator
  // (see app.dart's _showAlarmScreen) -- never as MaterialApp.home directly --
  // so push it the same way here. Dismiss's "open Focus" path reaches the
  // Navigator through appNavigatorKey, the same as app.dart.
  Widget wrap(FakePlannerRepository repo, {String segmentId = 's1', int notificationId = 42}) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AlarmScreen(segmentId: segmentId, notificationId: notificationId),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openAlarm(WidgetTester tester, FakePlannerRepository repo) async {
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the block name and start time', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(name: '약 먹기', startMinute: 9 * 60 + 30));

    await openAlarm(tester, repo);

    expect(find.text('약 먹기'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
  });

  testWidgets('shows a not-found state when the block no longer exists', (tester) async {
    final repo = FakePlannerRepository();

    await openAlarm(tester, repo);

    expect(find.text('구간을 찾을 수 없어요'), findsOneWidget);
    expect(find.byKey(const Key('alarm-dismiss-thumb')), findsNothing);
  });

  testWidgets('sliding to dismiss turns the alarm off (no completion) and opens Focus',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openAlarm(tester, repo);

    // Drag the thumb well past the dismissal threshold.
    await tester.drag(find.byKey(const Key('alarm-dismiss-thumb')), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(snapshots.last, isEmpty);
    expect(find.byType(AlarmScreen), findsNothing);
    expect(find.byType(FocusPage), findsOneWidget);
  });
}
