import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/debug_log.dart';
import 'core/error_reporting.dart';
import 'data/repositories/firestore/firestore_planner_repository.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

void main() {
  // runZonedGuarded + the two global handlers funnel EVERY uncaught error --
  // Flutter framework errors, async/platform errors, and the app's many
  // `unawaited(...)` writes that throw -- through reportError, so failures
  // that used to vanish silently leave a trail (and reach a crash reporter
  // once one is wired into reportError).
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) =>
        reportError(details.exception, details.stack, where: 'FlutterError');
    PlatformDispatcher.instance.onError = (error, stack) {
      reportError(error, stack, where: 'PlatformDispatcher');
      return true;
    };

    // Portrait-only: the circular dial / Focus / alarm layouts are designed
    // for a tall screen, and landscape squeezes them into overflow. Lock it
    // here (plus android:screenOrientation="portrait" in the manifest).
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Never throws -- see _startFirebase. Returns null if we couldn't get an
    // account this launch (offline, auth blocked); the app still starts.
    final uid = await _startFirebase();

    // UI first -- don't hold the first frame hostage behind a permission
    // dialog or a Firestore round trip. Notification permission/scheduling
    // runs right after, off the critical path (see below).
    runApp(const ProviderScope(child: App()));

    // No account yet -> nothing to schedule against. _retryAnonymousSignIn
    // keeps trying, and app.dart's _AccountAlarmSync schedules the moment a
    // repository appears, so a late sign-in still arms the alarms.
    if (uid != null) unawaited(_initNotificationsInBackground(uid));
  }, (error, stack) => reportError(error, stack, where: 'runZonedGuarded'));
}

/// Firebase init + "always signed in" -- and **never throws**.
///
/// Everything here used to run inline before `runApp`, so a single failure on
/// the startup path skipped `runApp` entirely and left the app frozen on its
/// splash screen forever. That is not a theoretical case: launching with no
/// connectivity (or with this build's signing key not yet allowed by the
/// Firebase API key restriction) made `signInAnonymously` throw, and the app
/// simply never appeared. An offline-capable app (Firestore persistence is on)
/// has no business refusing to start, so failures here degrade to "no account
/// yet" and the UI comes up regardless.
///
/// Returns the signed-in uid, or null if we couldn't get one this launch.
Future<String?> _startFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    // Only ship crash reports from release builds -- debug runs would otherwise
    // spam the console with noise from intentional/test errors.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
  } catch (e, st) {
    reportError(e, st, where: 'Firebase 초기화');
    return null; // Firebase 자체가 없으면 로그인도 불가 -- 재시도해도 소용없다.
  }

  // 항상 로그인 상태 보장: 아무 계정도 없으면 익명으로 시작.
  final existing = FirebaseAuth.instance.currentUser;
  if (existing != null) return existing.uid;

  try {
    // The timeout is for a *hung* request, not a failing one (offline fails
    // fast on its own) -- without it a stalled sign-in would hold the first
    // frame back, which is the very thing this function exists to prevent.
    final credential = await FirebaseAuth.instance
        .signInAnonymously()
        .timeout(const Duration(seconds: 10));
    return credential.user?.uid;
  } catch (e, st) {
    reportError(e, st, where: '익명 로그인');
    unawaited(_retryAnonymousSignIn());
    return null;
  }
}

/// Keeps trying to sign in after a failed start, so the app heals itself when
/// connectivity comes back instead of needing a manual restart.
///
/// Nothing here touches the UI: a successful sign-in makes `userChanges()`
/// emit, which rebuilds `plannerRepositoryProvider` and with it every screen
/// (and arms the alarms via `_AccountAlarmSync`). Backs off to a 1-minute
/// poll and gives up after roughly an hour -- long enough to cover "I turned
/// the wifi back on", short enough not to poll for the process's whole life.
Future<void> _retryAnonymousSignIn() async {
  var delay = const Duration(seconds: 5);
  const maxDelay = Duration(minutes: 1);
  for (var attempt = 0; attempt < 60; attempt++) {
    await Future<void>.delayed(delay);
    if (FirebaseAuth.instance.currentUser != null) return; // 다른 경로로 로그인됨
    try {
      await FirebaseAuth.instance.signInAnonymously();
      return;
    } catch (e) {
      // 재시도 실패는 흔한 일(계속 오프라인) -- Crashlytics로 올리면 같은
      // 오류가 수십 번 쌓이므로 여기서는 흔적만 남긴다.
      logSwallowed('익명 로그인 재시도', e);
    }
    delay = delay * 2 > maxDelay ? maxDelay : delay * 2;
  }
}

/// Notification plugin init, permission request, and the initial alarm
/// schedule -- run AFTER `runApp` so the first frame isn't blocked behind the
/// system permission dialogs or the initial Firestore reads. (Account-switch
/// rescheduling is handled by app.dart's `_AccountAlarmSync`.)
Future<void> _initNotificationsInBackground(String uid) async {
  try {
    final repository = FirestorePlannerRepository(uid);
    final notificationService = NotificationService(repository);
    await notificationService.init();
    await notificationService.requestPermissions();
    final segments = await repository.watchSegments().first;
    final settings = await repository.watchSettings().first;
    // 쉬는 날 여부는 rescheduleAll이 스스로 읽는다.
    await notificationService.rescheduleAll(segments, settings);
  } catch (e, st) {
    reportError(e, st, where: '초기 알림 스케줄');
  }
}
