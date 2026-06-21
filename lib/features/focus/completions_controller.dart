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
    return _ref
        .read(plannerRepositoryProvider)!
        .setCompletion(Completion.now(routineId, at: now));
  }

  // Lets the today-checklist screen un-check a routine someone marked done
  // by mistake -- the only other writer (Focus's 완료 button) never needs
  // to take this back, so this had no caller until that screen existed.
  Future<void> uncomplete(String routineId, {DateTime? now}) {
    final dateKey = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    return _ref.read(plannerRepositoryProvider)!.removeCompletion(dateKey, routineId);
  }
}
