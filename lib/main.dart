import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
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

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    // 항상 로그인 상태 보장: 아무 계정도 없으면 익명으로 시작.
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // UI first -- don't hold the first frame hostage behind a permission
    // dialog or a Firestore round trip. Notification permission/scheduling
    // runs right after, off the critical path (see below).
    runApp(const ProviderScope(child: App()));

    unawaited(_initNotificationsInBackground(uid));
  }, (error, stack) => reportError(error, stack, where: 'runZonedGuarded'));
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
    await notificationService.rescheduleAll(segments, settings);
  } catch (e, st) {
    reportError(e, st, where: '초기 알림 스케줄');
  }
}
