import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/providers.dart';
import 'data/repositories/firestore/firestore_planner_repository.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // Anonymous auth for Firestore authentication requirement.
  var user = FirebaseAuth.instance.currentUser;
  user ??= (await FirebaseAuth.instance.signInAnonymously()).user;

  // 고정 UID: 재설치 시 익명 UID가 바뀌어도 기존 데이터를 유지하기 위해
  // 원본 사용자 UID를 직접 지정한다.
  const fixedUid = 'LqBWKlX59ucI6KQ7W2rrlVZtQNv1';
  final repository = FirestorePlannerRepository(fixedUid);

  final notificationService = NotificationService(repository);
  await notificationService.init();
  await notificationService.requestPermissions();
  final routines = await repository.watchRoutines().first;
  final settings = await repository.watchSettings().first;
  await notificationService.rescheduleAll(routines, settings);

  runApp(ProviderScope(
    overrides: [
      plannerRepositoryProvider.overrideWithValue(repository),
      notificationServiceProvider.overrideWithValue(notificationService),
    ],
    child: const App(),
  ));
}
