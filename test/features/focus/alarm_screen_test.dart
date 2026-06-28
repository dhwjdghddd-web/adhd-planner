import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/data/today.dart';
import 'package:adhd_planner/features/focus/alarm_screen.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/memos/quick_add_button.dart';
import 'package:adhd_planner/services/notification_service.dart';

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

/// Records the order [cancelNotification]/[scheduleSnooze] *complete* in, with
/// [cancelNotification] artificially slow -- so a regression that fires the
/// two unawaited and unsequenced (racing cancel-vs-reschedule of the same
/// AlarmManager entry) would show scheduleSnooze finishing first here, the
/// same way it could land first against the real native channel.
class _OrderRecordingNotificationService extends NotificationService {
  _OrderRecordingNotificationService() : super(FakePlannerRepository());

  final List<String> order = [];

  @override
  Future<void> cancelNotification(int id) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    order.add('cancel');
  }

  @override
  Future<void> scheduleSnooze({required Segment segment, required AppSettings settings}) async {
    order.add('schedule');
  }
}

void main() {
  // AlarmScreen is pushed as a full-screen route over the existing Navigator
  // (see app.dart's _showAlarmScreen) -- never as MaterialApp.home directly --
  // so push it the same way here. Dismiss's "open Focus" path reaches the
  // Navigator through appNavigatorKey, the same as app.dart.
  Widget wrap(
    FakePlannerRepository repo, {
    String segmentId = 's1',
    int notificationId = 42,
    NotificationService? notificationService,
  }) {
    return ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
        if (notificationService != null)
          notificationServiceProvider.overrideWithValue(notificationService),
      ],
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

  Future<void> openAlarm(
    WidgetTester tester,
    FakePlannerRepository repo, {
    NotificationService? notificationService,
  }) async {
    await tester.pumpWidget(wrap(repo, notificationService: notificationService));
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

  testWidgets('dismissing while already on a Focus screen leaves exactly one Focus '
      '(no stacked double-Focus)', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final navigator = appNavigatorKey.currentState!;
    // The user is already viewing this block in Focus when the alarm fires.
    navigator.push(MaterialPageRoute<void>(builder: (_) => FocusPage.forBlock(_block())));
    await tester.pumpAndSettle();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const AlarmScreen(segmentId: 's1', notificationId: 42),
    ));
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(const Key('alarm-dismiss-thumb')), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.byType(AlarmScreen), findsNothing);
    // Exactly one Focus, not the old one plus a freshly pushed one.
    expect(find.byType(FocusPage), findsOneWidget);
  });

  testWidgets('shows the two lighter exits below the slide, labelled with the '
      "configured snooze minutes", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());
    await repo.saveSettings(const AppSettings.defaults().copyWith(snoozeMinutes: 15));

    await openAlarm(tester, repo);

    expect(find.text('15분 뒤 다시'), findsOneWidget);
    expect(find.text('오늘은 건너뛰기'), findsOneWidget);
  });

  testWidgets("tapping '다시' closes the alarm screen without opening Focus or "
      'recording a completion (a snooze is "later", not "starting now")',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openAlarm(tester, repo);
    await tester.tap(find.textContaining('분 뒤 다시'));
    await tester.pumpAndSettle();

    expect(find.byType(AlarmScreen), findsNothing);
    expect(find.byType(FocusPage), findsNothing);
    expect(snapshots.last, isEmpty);
  });

  testWidgets(
      "tapping '다시' cancels today's ring before arming the snooze, even when "
      'cancelling is the slower of the two (regression: firing both unawaited '
      "and unsequenced let a slow cancel land *after* schedule and silently "
      "wipe out the just-armed snooze alarm)", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());
    final service = _OrderRecordingNotificationService();

    await openAlarm(tester, repo, notificationService: service);
    await tester.tap(find.textContaining('분 뒤 다시'));
    await tester.pumpAndSettle();

    expect(service.order, ['cancel', 'schedule']);
  });

  testWidgets("tapping '오늘은 건너뛰기' closes the alarm screen and records "
      "today's skip, without opening Focus", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(id: 's1'));

    await openAlarm(tester, repo);
    await tester.tap(find.text('오늘은 건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.byType(AlarmScreen), findsNothing);
    expect(find.byType(FocusPage), findsNothing);

    final skips = await repo.watchAlarmSkips().first;
    expect(skippedBlockIdsOn(skips), contains('s1'));
  });
}
