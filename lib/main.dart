import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/repositories/firestore/firestore_planner_repository.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  // 항상 로그인 상태 보장: 아무 계정도 없으면 익명으로 시작.
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  final uid = FirebaseAuth.instance.currentUser!.uid;

  // 초기 알람 스케줄은 여기서 한 번. (계정 전환 시 재스케줄은 app.dart의
  // _AccountAlarmSync.) 이 main 경로는 위젯 테스트가 타지 않으므로 플랫폼
  // 채널을 써도 안전.
  final repository = FirestorePlannerRepository(uid);
  final notificationService = NotificationService(repository);
  await notificationService.init();
  await notificationService.requestPermissions();
  final segments = await repository.watchSegments().first;
  final settings = await repository.watchSettings().first;
  await notificationService.rescheduleAll(segments, settings);

  // repo/service override는 더 이상 주입하지 않는다 — provider가 auth에서
  // 스스로 빌드한다(data/providers.dart).
  runApp(const ProviderScope(child: App()));
}
