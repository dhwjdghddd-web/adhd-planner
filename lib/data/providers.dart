import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_settings.dart';
import 'models/completion.dart';
import 'models/memo.dart';
import 'models/routine.dart';
import 'models/segment.dart';
import 'repositories/planner_repository.dart';

/// Injection point for the storage backend. `main.dart` overrides this with
/// a concrete [HivePlannerRepository] (STEP 3-8) or, once Firebase auth is
/// wired up, a Firestore-backed implementation (STEP 9) — no other code in
/// the app needs to change when that swap happens.
final plannerRepositoryProvider = Provider<PlannerRepository>((ref) {
  throw UnimplementedError(
    'plannerRepositoryProvider must be overridden in main.dart with a '
    'concrete PlannerRepository before runApp().',
  );
});

final segmentsProvider = StreamProvider<List<Segment>>(
  (ref) => ref.watch(plannerRepositoryProvider).watchSegments(),
);

final routinesProvider = StreamProvider<List<Routine>>(
  (ref) => ref.watch(plannerRepositoryProvider).watchRoutines(),
);

final memosProvider = StreamProvider<List<Memo>>(
  (ref) => ref.watch(plannerRepositoryProvider).watchMemos(),
);

final completionsProvider = StreamProvider<List<Completion>>(
  (ref) => ref.watch(plannerRepositoryProvider).watchCompletions(),
);

final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(plannerRepositoryProvider).watchSettings(),
);
