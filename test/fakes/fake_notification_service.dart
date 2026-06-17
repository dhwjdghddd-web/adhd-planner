import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/services/notification_service.dart';

import 'fake_planner_repository.dart';

/// No-op stand-in for [NotificationService] in widget tests. The real
/// service talks to the `flutter_local_notifications` platform channel,
/// which doesn't exist under `flutter test` — so widget tests that exercise
/// `RoutinesController` (which triggers a reschedule on every write) need
/// this in place of the real service. Records calls so a test can assert a
/// reschedule was triggered without touching any plugin.
class FakeNotificationService extends NotificationService {
  FakeNotificationService() : super(FakePlannerRepository());

  final List<List<Routine>> rescheduleCalls = [];

  @override
  Future<void> rescheduleAll(List<Routine> routines) async {
    rescheduleCalls.add(routines);
  }
}
