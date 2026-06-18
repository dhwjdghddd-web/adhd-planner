import 'package:flutter/services.dart';

const _channel = MethodChannel('com.adhdplanner.adhd_planner/alarm_sound');

/// What the user picked from Android's native alarm-sound dialog.
class AlarmSoundPick {
  const AlarmSoundPick({required this.uri, required this.label});

  final String uri;
  final String label;
}

/// Opens Android's own "choose an alarm sound" picker (the same dialog the
/// system Clock app uses) via [MainActivity]'s platform channel — there's no
/// need to build a custom list when the OS already has one covering every
/// ringtone the system and the user's other apps installed.
///
/// Returns null if the user cancelled, picked "Silent", or this is running
/// somewhere without that platform channel (iOS, tests) — callers should
/// leave the current selection untouched in that case rather than clearing
/// it.
Future<AlarmSoundPick?> pickAlarmSound({String? currentUri}) async {
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickAlarmSound',
      {'currentUri': currentUri},
    );
    if (result == null) return null;
    return AlarmSoundPick(uri: result['uri'] as String, label: result['label'] as String);
  } catch (_) {
    return null;
  }
}

/// Plays [pattern] (the same `[pause, on, off, on, off, ...]` millisecond
/// list the real alarm channel uses) once on the device's vibration motor,
/// so picking a pattern in Settings is a felt choice rather than a guess
/// from the label alone. No-op if there's no platform channel (iOS, tests).
Future<void> previewVibration(List<int> pattern) async {
  try {
    // .toList() rather than passing a typed list (e.g. Int64List) through
    // as-is: a plain Dart List always arrives as a Java/Kotlin List via the
    // standard method codec, which is what MainActivity.kt's handler
    // expects -- a typed list instead maps to a raw long[].
    await _channel.invokeMethod('previewVibration', {'vibrationPattern': pattern.toList()});
  } catch (_) {
    // No platform channel available -- nothing to preview.
  }
}
