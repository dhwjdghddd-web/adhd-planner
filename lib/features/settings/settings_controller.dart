import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../data/providers.dart';

final settingsControllerProvider = Provider<SettingsController>(
  (ref) => SettingsController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for the settings and
/// onboarding screens, mirroring `RoutinesController`/`SegmentsController`.
class SettingsController {
  SettingsController(this._ref);

  final Ref _ref;

  Future<void> save(AppSettings settings) =>
      _ref.read(plannerRepositoryProvider).saveSettings(settings);
}
