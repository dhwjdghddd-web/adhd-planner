import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// The single chokepoint every non-fatal-but-noteworthy error flows through,
/// so silent failures (an offline Firestore write that never resolves, a
/// denied permission, an `unawaited` future that throws) leave a trail
/// instead of vanishing.
///
/// `main.dart` installs the global handlers ([FlutterError.onError],
/// [PlatformDispatcher.instance.onError], and a `runZonedGuarded` zone) that
/// all route here -- so every uncaught Flutter/async error, including the
/// app's many `unawaited(...)` writes, is captured in one place, and forwarded
/// to Crashlytics so release builds aren't blind to them.
void reportError(Object error, StackTrace? stackTrace, {String? where}) {
  if (kDebugMode) {
    debugPrint('[adhd_planner] ${where ?? '오류'}: $error');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
  // Best-effort: never let the reporter itself throw (e.g. before Firebase is
  // initialized, or under flutter test where there's no Crashlytics channel).
  try {
    FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: where,
      fatal: false,
    );
  } catch (_) {
    // Crashlytics unavailable here -- the debug log above is the fallback.
  }
}
