import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'data/providers.dart';
import 'data/repositories/local/hive_planner_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final repository = await HivePlannerRepository.open();

  runApp(ProviderScope(
    overrides: [plannerRepositoryProvider.overrideWithValue(repository)],
    child: const App(),
  ));
}
