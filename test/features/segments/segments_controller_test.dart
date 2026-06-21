import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/segments/segments_controller.dart';

import '../../fakes/fake_planner_repository.dart';

Segment _segment({
  required String id,
  required int startMinute,
  required int endMinute,
}) {
  return Segment(
    id: id,
    name: id,
    colorValue: 0xFF000000,
    iconKey: '',
    startMinute: startMinute,
    endMinute: endMinute,
    order: 0,
  );
}

Routine _routine({required String id, required String? segmentId, required int startMinute}) {
  return Routine(id: id, segmentId: segmentId, title: id, startMinute: startMinute);
}

void main() {
  group('SegmentsController.delete re-homes affected routines', () {
    test('a routine drops to 구간 없음 when no remaining segment covers it', () async {
      final repo = FakePlannerRepository();
      await repo.upsertSegment(_segment(id: 'morning', startMinute: 6 * 60, endMinute: 12 * 60));
      await repo.upsertRoutine(_routine(id: 'r1', segmentId: 'morning', startMinute: 8 * 60));

      final container = ProviderContainer(
        overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(segmentsControllerProvider).delete('morning');

      final routines = await repo.watchRoutines().first;
      expect(routines.single.segmentId, isNull);
      expect((await repo.watchSegments().first), isEmpty);
    });

    test('a routine re-homes to an overlapping segment that still covers its start', () async {
      final repo = FakePlannerRepository();
      // Two overlapping segments both cover 08:00.
      await repo.upsertSegment(_segment(id: 'morning', startMinute: 6 * 60, endMinute: 12 * 60));
      await repo.upsertSegment(_segment(id: 'work', startMinute: 7 * 60, endMinute: 18 * 60));
      await repo.upsertRoutine(_routine(id: 'r1', segmentId: 'morning', startMinute: 8 * 60));

      final container = ProviderContainer(
        overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(segmentsControllerProvider).delete('morning');

      final routines = await repo.watchRoutines().first;
      expect(routines.single.segmentId, 'work');
    });

    test('routines in other segments are left untouched', () async {
      final repo = FakePlannerRepository();
      await repo.upsertSegment(_segment(id: 'morning', startMinute: 6 * 60, endMinute: 12 * 60));
      await repo.upsertSegment(_segment(id: 'evening', startMinute: 18 * 60, endMinute: 22 * 60));
      await repo.upsertRoutine(_routine(id: 'r1', segmentId: 'morning', startMinute: 8 * 60));
      await repo.upsertRoutine(_routine(id: 'r2', segmentId: 'evening', startMinute: 20 * 60));

      final container = ProviderContainer(
        overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      await container.read(segmentsControllerProvider).delete('morning');

      final routines = {for (final r in await repo.watchRoutines().first) r.id: r};
      expect(routines['r1']!.segmentId, isNull); // re-homed (no overlap)
      expect(routines['r2']!.segmentId, 'evening'); // untouched
    });
  });
}
