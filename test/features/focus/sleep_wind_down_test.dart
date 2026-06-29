import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/features/focus/sleep_wind_down.dart';

Segment _block({
  String name = '오전',
  String iconKey = 'wb_sunny',
  List<String> microSteps = const [],
}) {
  return Segment(
    id: 's1',
    name: name,
    colorValue: 0xFF000000,
    iconKey: iconKey,
    startMinute: 0,
    endMinute: 60,
    order: 0,
    microSteps: microSteps,
  );
}

void main() {
  group('isSleepBlock', () {
    test('true for the canonical 수면 template (bedtime icon)', () {
      expect(isSleepBlock(_block(name: '수면', iconKey: 'bedtime')), true);
    });

    test('true for any block whose icon is bedtime, regardless of name', () {
      expect(isSleepBlock(_block(name: '밤 루틴', iconKey: 'bedtime')), true);
    });

    test("true for any block named with '수면' in it, regardless of icon", () {
      expect(isSleepBlock(_block(name: '낮잠 수면', iconKey: 'wb_sunny')), true);
    });

    test('false for an ordinary block with neither signal', () {
      expect(
        isSleepBlock(_block(name: '아침 운동', iconKey: 'fitness_center')),
        false,
      );
    });

    test("false for the merely night-themed nights_stay icon without '수면' "
        "in the name (deliberately not treated as sleep)", () {
      expect(
        isSleepBlock(_block(name: '야간 산책', iconKey: 'nights_stay')),
        false,
      );
    });
  });

  group('SleepWindDown widget', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets(
      'shows the block name, a 폰 내려놓기 nudge, and the remaining message',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            SleepWindDown(
              segment: _block(name: '수면', iconKey: 'bedtime'),
              reduceMotion: false,
              remainingMessage: '7시간 30분 남음',
            ),
          ),
        );
        await tester.pump();

        expect(find.text('수면'), findsOneWidget);
        expect(find.text('이제 폰 내려놓아요'), findsOneWidget);
        expect(find.text('7시간 30분 남음'), findsOneWidget);
        // Breathing guide cycles through these two prompts -- starts on 들이쉬세요.
        expect(find.text('들이쉬세요'), findsOneWidget);
      },
    );

    testWidgets('omits the remaining message when null (review mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          SleepWindDown(
            segment: _block(name: '수면', iconKey: 'bedtime'),
            reduceMotion: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('남음'), findsNothing);
    });

    testWidgets(
      'reduceMotion shows a static guide instead of the animated one',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            SleepWindDown(
              segment: _block(name: '수면', iconKey: 'bedtime'),
              reduceMotion: true,
            ),
          ),
        );
        await tester.pump();

        expect(find.text('천천히 숨을 쉬어보세요'), findsOneWidget);
        expect(find.text('들이쉬세요'), findsNothing);
        expect(find.text('내쉬세요'), findsNothing);

        // No animation running -- pumping time forward shouldn't change anything
        // or leave a pending timer/ticker behind.
        await tester.pump(const Duration(seconds: 10));
        expect(find.text('천천히 숨을 쉬어보세요'), findsOneWidget);
      },
    );

    testWidgets(
      'the breathing prompt alternates between 들이쉬세요 and 내쉬세요 over time',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            SleepWindDown(
              segment: _block(name: '수면', iconKey: 'bedtime'),
              reduceMotion: false,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('들이쉬세요'), findsOneWidget);

        // Past the 4s inhale half-cycle -- now exhaling.
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('내쉬세요'), findsOneWidget);
      },
    );
  });
}
