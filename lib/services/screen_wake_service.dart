import 'package:flutter/services.dart';

import '../core/debug_log.dart';

const _channel = MethodChannel('com.adhdplanner.adhd_planner/screen');

/// Turns the Android FLAG_KEEP_SCREEN_ON window flag on/off (the "화면 항상
/// 켜두기" settings toggle). The flag only holds while the app is foreground,
/// so this never keeps the screen awake once the app is backgrounded. No-op
/// with no platform channel (iOS, flutter test).
Future<void> setKeepScreenOn(bool on) async {
  try {
    await _channel.invokeMethod('setKeepScreenOn', {'on': on});
  } catch (e) {
    logSwallowed('setKeepScreenOn', e);
  }
}
