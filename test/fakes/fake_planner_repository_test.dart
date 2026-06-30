import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/checkin.dart';
import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/models/segment.dart';

import 'fake_planner_repository.dart';

void main() {
  test('deleteAllData clears every collection and resets settings', () async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(
      const Segment(
        id: 's1',
        name: 'b',
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 0,
        endMinute: 60,
        order: 0,
      ),
    );
    await repo.addMemo(
      const Memo(
        id: 'm1',
        text: 'note',
        source: MemoSource.text,
        createdAtIso: '2026-06-30T10:00:00.000',
      ),
    );
    await repo.saveCheckin(
      const Checkin(dateKey: '2026-06-30', mood: 3, energy: 3),
    );

    expect(await repo.watchSegments().first, isNotEmpty);
    expect(await repo.watchMemos().first, isNotEmpty);
    expect(await repo.watchCheckins().first, isNotEmpty);

    await repo.deleteAllData();

    expect(await repo.watchSegments().first, isEmpty);
    expect(await repo.watchMemos().first, isEmpty);
    expect(await repo.watchCheckins().first, isEmpty);
  });
}
