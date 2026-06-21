import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

/// Records a deliberately-swallowed, best-effort failure so on-device
/// debugging has a breadcrumb where there used to be a bare `catch (_) {}`.
///
/// These call sites are non-fatal by design — a missing alarm channel still
/// leaves an ordinary notification, 미루기 just no-ops if the native side
/// isn't there, etc. — so this never rethrows and does nothing in release
/// builds. [MissingPluginException] is filtered out because it's the
/// *expected* "no native side" case under `flutter test` and unsupported
/// platforms; logging it would just spam every test run. Anything else is a
/// real failure on a real device, which is exactly what was invisible before.
void logSwallowed(String where, Object error) {
  if (error is MissingPluginException) return;
  if (kDebugMode) debugPrint('[adhd_planner] $where 실패(무시됨): $error');
}
