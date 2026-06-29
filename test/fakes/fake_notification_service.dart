import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/services/notification_service.dart';

import 'fake_planner_repository.dart';

/// No-op stand-in for [NotificationService] in widget tests. The real service
/// talks to the `flutter_local_notifications` platform channel, which doesn't
/// exist under `flutter test` — so widget tests that exercise
/// `SegmentsController` (which triggers a reschedule on every write) need this
/// in place of the real service. Records calls so a test can assert a
/// reschedule was triggered without touching any plugin.
class FakeNotificationService extends NotificationService {
  FakeNotificationService() : super(FakePlannerRepository());

  final List<List<Segment>> rescheduleCalls = [];

  /// Each call's [knownIds], so a test can assert logout wiped the device's
  /// alarms (and with which ids) without touching any plugin.
  final List<List<int>> cancelEverythingCalls = [];

  /// Each call's (endAt, title, body), so a test can assert the Focus
  /// timer's end notification was (re)scheduled without touching any plugin.
  final List<({DateTime endAt, String title, String body})> timerEndCalls = [];
  int timerEndCancelCount = 0;

  @override
  Future<void> rescheduleAll(List<Segment> segments, AppSettings settings) async {
    rescheduleCalls.add(segments);
  }

  @override
  Future<void> cancelEverything({Iterable<int> knownIds = const []}) async {
    cancelEverythingCalls.add(knownIds.toList());
  }

  @override
  Future<void> scheduleTimerEnd({
    required DateTime endAt,
    required String title,
    required String body,
  }) async {
    timerEndCalls.add((endAt: endAt, title: title, body: body));
  }

  @override
  Future<void> cancelTimerEnd() async {
    timerEndCancelCount++;
  }
}
