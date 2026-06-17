import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/providers.dart';
import 'data/repositories/local/hive_planner_repository.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final repository = await HivePlannerRepository.open();

  final notificationService = NotificationService(repository);
  await notificationService.init();
  await notificationService.requestPermissions();
  final routines = await repository.watchRoutines().first;
  await notificationService.rescheduleAll(routines);

  runApp(ProviderScope(
    overrides: [
      plannerRepositoryProvider.overrideWithValue(repository),
      notificationServiceProvider.overrideWithValue(notificationService),
    ],
    child: const App(),
  ));
}
