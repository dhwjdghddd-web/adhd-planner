import 'package:flutter/foundation.dart';

/// The single chokepoint every non-fatal-but-noteworthy error flows through,
/// so silent failures (an offline Firestore write that never resolves, a
/// denied permission, an `unawaited` future that throws) leave a trail
/// instead of vanishing.
///
/// `main.dart` installs the global handlers ([FlutterError.onError],
/// [PlatformDispatcher.instance.onError], and a `runZonedGuarded` zone) that
/// all route here -- so every uncaught Flutter/async error, including the
/// app's many `unawaited(...)` writes, is captured in one place. Hook a crash
/// reporter (Crashlytics/Sentry) in here when one is added.
void reportError(Object error, StackTrace? stackTrace, {String? where}) {
  if (kDebugMode) {
    debugPrint('[adhd_planner] ${where ?? '오류'}: $error');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
  // TODO(crash-reporting): forward to Crashlytics/Sentry once configured, so
  // release builds aren't blind to these.
}
