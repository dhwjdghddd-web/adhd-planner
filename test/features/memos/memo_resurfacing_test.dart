import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/features/memos/memo_resurfacing.dart';

Memo _memo(String id, String text, {required DateTime createdAt, bool reviewed = false}) {
  return Memo(
    id: id,
    text: text,
    source: MemoSource.text,
    createdAtIso: createdAt.toIso8601String(),
    reviewed: reviewed,
  );
}

void main() {
  group('oldestNudgeworthyMemo', () {
    final now = DateTime(2026, 6, 29, 12);

    test('returns null when there are no memos at all', () {
      expect(oldestNudgeworthyMemo(const [], now), isNull);
    });

    test('returns null when the only memo is fresh (under the min age)', () {
      final memos = [_memo('m1', '방금', createdAt: now.subtract(const Duration(hours: 1)))];
      expect(oldestNudgeworthyMemo(memos, now), isNull);
    });

    test('returns null when the only old-enough memo is already reviewed', () {
      final memos = [
        _memo('m1', '확인함', createdAt: now.subtract(const Duration(days: 10)), reviewed: true),
      ];
      expect(oldestNudgeworthyMemo(memos, now), isNull);
    });

    test('returns a memo exactly at the min age boundary', () {
      final memos = [_memo('m1', '딱 3일', createdAt: now.subtract(kMemoNudgeMinAge))];
      expect(oldestNudgeworthyMemo(memos, now)?.id, 'm1');
    });

    test('picks the single oldest qualifying memo, not the most recent', () {
      final memos = [
        _memo('newer', '5일 전', createdAt: now.subtract(const Duration(days: 5))),
        _memo('oldest', '10일 전', createdAt: now.subtract(const Duration(days: 10))),
        _memo('newest-unqualified', '오늘', createdAt: now),
      ];
      expect(oldestNudgeworthyMemo(memos, now)?.id, 'oldest');
    });

    test('skips reviewed memos even when they are the oldest', () {
      final memos = [
        _memo('reviewed-oldest', '확인된 옛 메모',
            createdAt: now.subtract(const Duration(days: 20)), reviewed: true),
        _memo('unreviewed', '안 확인된 메모', createdAt: now.subtract(const Duration(days: 5))),
      ];
      expect(oldestNudgeworthyMemo(memos, now)?.id, 'unreviewed');
    });
  });
}
