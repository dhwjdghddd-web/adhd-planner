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

/// Whether the app is currently showing on a foldable **cover** screen --
/// i.e. a non-default built-in display (see MainActivity getDisplayInfo).
/// Returns false on a normal/main display, and false (safe default) when
/// there's no platform channel (iOS, flutter test).
Future<bool> queryOnCoverDisplay() async {
  try {
    final info = await _channel.invokeMapMethod<String, dynamic>(
      'getDisplayInfo',
    );
    if (info == null) return false;
    return (info['isDefault'] as bool?) == false;
  } catch (e) {
    logSwallowed('getDisplayInfo', e);
    return false;
  }
}
