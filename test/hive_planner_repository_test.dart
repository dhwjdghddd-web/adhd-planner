import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/repositories/local/hive_planner_repository.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hive_planner_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Segment sampleSegment() => const Segment(
        id: 's1',
        name: '오전',
        colorValue: 0xFF2E7D8C,
        iconKey: 'wb_sunny',
        startMinute: 360,
        endMinute: 720,
        order: 0,
      );

  test('upsertSegment emits through watchSegments', () async {
    final repo = await HivePlannerRepository.open();
    addTearDown(repo.close);

    final emission = repo.watchSegments().firstWhere((list) => list.isNotEmpty);
    await repo.upsertSegment(sampleSegment());
    final result = await emission;

    expect(result, hasLength(1));
    expect(result.first.id, 's1');
    expect(result.first.name, '오전');
    expect(result.first.lengthMinutes, 360);
  });

  test('deleteSegment removes the entity', () async {
    final repo = await HivePlannerRepository.open();
    addTearDown(repo.close);

    await repo.upsertSegment(sampleSegment());
    await repo.deleteSegment('s1');
    final result = await repo.watchSegments().first;

    expect(result, isEmpty);
  });

  test('data persists across repository reopen (simulated app restart)', () async {
    final repo1 = await HivePlannerRepository.open();
    await repo1.upsertSegment(sampleSegment());
    await repo1.close();

    final repo2 = await HivePlannerRepository.open();
    addTearDown(repo2.close);
    final result = await repo2.watchSegments().first;

    expect(result, hasLength(1));
    expect(result.first.name, '오전');
  });
}
