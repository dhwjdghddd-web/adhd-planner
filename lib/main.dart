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

  // Anonymous auth: no sign-in UI yet (STEP 9 just wires the cloud backend
  // behind the same Repository interface). STEP 12 adds an upgrade path to
  // a real Google/Apple account from this same anonymous uid.
  var user = FirebaseAuth.instance.currentUser;
  user ??= (await FirebaseAuth.instance.signInAnonymously()).user;

  final repository = FirestorePlannerRepository(user!.uid);

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
