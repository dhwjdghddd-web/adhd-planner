import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/completion.dart';
import '../../data/providers.dart';

final completionsControllerProvider = Provider<CompletionsController>(
  (ref) => CompletionsController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for recording routine
/// completions from the focus screen, mirroring `RoutinesController`.
class CompletionsController {
  CompletionsController(this._ref);

  final Ref _ref;

  Future<void> complete(String routineId, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(n);
    return _ref.read(plannerRepositoryProvider).setCompletion(
          Completion(
            dateKey: dateKey,
            routineId: routineId,
            completedAtIso: n.toIso8601String(),
          ),
        );
  }
}
