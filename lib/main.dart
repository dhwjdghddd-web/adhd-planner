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

import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/debug_log.dart';
import 'core/error_reporting.dart';
import 'data/providers.dart';
import 'data/repositories/firestore/firestore_planner_repository.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) =>
        reportError(details.exception, details.stack, where: 'FlutterError');
    PlatformDispatcher.instance.onError = (error, stack) {
      reportError(error, stack, where: 'PlatformDispatcher');
      return true;
    };

    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final prefs = await SharedPreferences.getInstance();

    final uid = await _startFirebase();

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (uid != null) initialUidProvider.overrideWithValue(uid),
        ],
        child: const App(),
      ),
    );

    if (uid != null) unawaited(_initNotificationsInBackground(uid));
  }, (error, stack) => reportError(error, stack, where: 'runZonedGuarded'));
}

/// Firebase init + "always signed in" -- and **never throws**.
Future<String?> _startFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 4));
  } catch (e, st) {
    reportError(e, st, where: 'Firebase 초기화');
  }

  try {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
  } catch (e) {
    // WearListenerService 등 백그라운드에서 네이티브 Firestore가 이미 실행 중인 경우
    // settings 재설정 시 예외가 발생할 수 있으므로 안전하게 격리합니다.
    logSwallowed('Firestore settings 적용', e);
  }

  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      !kDebugMode,
    );
  } catch (e) {
    logSwallowed('Crashlytics 초기화', e);
  }

  // 항상 로그인 상태 보장: 아무 계정도 없으면 익명으로 시작.
  final existing = FirebaseAuth.instance.currentUser;
  if (existing != null) return existing.uid;

  try {
    final credential = await FirebaseAuth.instance
        .signInAnonymously()
        .timeout(const Duration(seconds: 5));
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
