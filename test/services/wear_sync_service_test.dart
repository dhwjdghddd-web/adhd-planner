import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/micro_step_move.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/services/wear_sync_service.dart';

Segment _block({
  required String id,
  required String name,
  required int startMinute,
  required int endMinute,
  List<String> microSteps = const [],
}) {
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: endMinute,
    order: 0,
    microSteps: microSteps,
  );
}

void main() {
  // A fixed "now" away from midnight so dateKey/moves are unambiguous.
  final now = DateTime(2026, 7, 6, 10, 30);

  group('buildChecklistJson', () {
    test(
      'includes EVERY block with its times -- even ones with no checklist '
      'items (regression: filtering those out hid a just-starting block from '
      'the watch alarm and checklist entirely)',
      () {
        final json = jsonDecode(
          buildChecklistJson(
            segments: [
              _block(id: 'a', name: '아침', startMinute: 600, endMinute: 660),
              _block(
                id: 'b',
                name: '오후',
                startMinute: 630,
                endMinute: 720,
                microSteps: const ['물 마시기'],
              ),
            ],
            progress: const [],
            moves: const [],
            now: now,
          ),
        ) as Map<String, dynamic>;

        final blocks = json['blocks'] as List<dynamic>;
        expect(blocks, hasLength(2));
        final a = blocks[0] as Map<String, dynamic>;
        expect(a['blockId'], 'a');
        expect(a['name'], '아침');
        expect(a['start'], 600);
        expect(a['end'], 660);
        expect(a['items'], isEmpty);
        expect(json['dateKey'], '2026-07-06');
      },
    );

    test('restToday flag rides along (default false, set true on rest days)', () {
      final blocks = [
        _block(id: 'a', name: '아침', startMinute: 600, endMinute: 660),
      ];
      final off =
          jsonDecode(
                buildChecklistJson(
                  segments: blocks,
                  progress: const [],
                  moves: const [],
                  now: now,
                ),
              )
              as Map<String, dynamic>;
      expect(off['restToday'], false);

      final on =
          jsonDecode(
                buildChecklistJson(
                  segments: blocks,
                  progress: const [],
                  moves: const [],
                  restToday: true,
                  now: now,
                ),
              )
              as Map<String, dynamic>;
      expect(on['restToday'], true);
    });

    test('items carry home identity and TODAY\'s checked state only', () {
      final json = jsonDecode(
        buildChecklistJson(
          segments: [
            _block(
              id: 'a',
              name: '아침',
              startMinute: 600,
              endMinute: 660,
              microSteps: const ['물', '약'],
            ),
          ],
          progress: [
            // Today: index 1 checked. Yesterday's record must be ignored.
            MicroStepProgress(
              dateKey: '2026-07-06',
              segmentId: 'a',
              checkedIndices: const [1],
            ),
            MicroStepProgress(
              dateKey: '2026-07-05',
              segmentId: 'a',
              checkedIndices: const [0],
            ),
          ],
          moves: const [],
          now: now,
        ),
      ) as Map<String, dynamic>;

      final items =
          ((json['blocks'] as List<dynamic>).single
                  as Map<String, dynamic>)['items']
              as List<dynamic>;
      expect(items, hasLength(2));
      expect((items[0] as Map<String, dynamic>)['checked'], false);
      final second = items[1] as Map<String, dynamic>;
      expect(second['checked'], true);
      expect(second['segmentId'], 'a');
      expect(second['index'], 1);
    });

    test('"오늘만 여기서" move shows the item under the target block, keyed by '
        'its home identity', () {
      final json = jsonDecode(
        buildChecklistJson(
          segments: [
            _block(
              id: 'home',
              name: '아침',
              startMinute: 600,
              endMinute: 660,
              microSteps: const ['옮길 항목'],
            ),
            _block(id: 'target', name: '오후', startMinute: 700, endMinute: 800),
          ],
          progress: const [],
          moves: [
            MicroStepMove(
              dateKey: '2026-07-06',
              homeSegmentId: 'home',
              stepIndex: 0,
              targetSegmentId: 'target',
            ),
          ],
          now: now,
        ),
      ) as Map<String, dynamic>;

      final blocks = json['blocks'] as List<dynamic>;
      final home = blocks[0] as Map<String, dynamic>;
      final target = blocks[1] as Map<String, dynamic>;
      expect(home['items'], isEmpty); // moved away today
      final moved =
          (target['items'] as List<dynamic>).single as Map<String, dynamic>;
      expect(moved['text'], '옮길 항목');
      // Home identity preserved so a watch toggle writes to the right doc.
      expect(moved['segmentId'], 'home');
      expect(moved['index'], 0);
    });
  });
}
