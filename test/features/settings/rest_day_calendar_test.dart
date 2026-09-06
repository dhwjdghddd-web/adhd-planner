import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/settings/rest_day_calendar_sheet.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  testWidgets('RestDayCalendarSheet renders month and toggles rest days', (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          plannerRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(
          home: RestDayCalendarSheet(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check title and today's day number
    expect(find.text('스케줄 & 프리셋 캘린더'), findsOneWidget);
    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);
    expect(find.text('${now.day}'), findsOneWidget);

    // Tap on today's cell to select it
    await tester.tap(find.text('${now.day}'));
    await tester.pumpAndSettle();

    // Bottom sheet shows up with preset actions
    expect(find.text('선택한 1개 날짜에 프리셋 배정'), findsOneWidget);

    // Tap '쉬는 날' preset button to apply
    await tester.tap(find.widgetWithText(FilledButton, '쉬는 날'));
    await tester.pumpAndSettle();

    final restDays = await repo.watchRestDays().first;
    expect(restDays.map((r) => r.dateKey), contains(todayKey));
    expect(restDays.firstWhere((r) => r.dateKey == todayKey).presetId, 'rest');

    // Wait for snackbar to dismiss
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Tap today again to select
    await tester.tap(find.text('${now.day}'));
    await tester.pumpAndSettle();

    // Ensure button is visible in horizontal scroll and tap
    await tester.ensureVisible(find.text('기본값(해제)'));
    await tester.tap(find.text('기본값(해제)'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final restDaysAfter = await repo.watchRestDays().first;
    expect(restDaysAfter.map((r) => r.dateKey), isNot(contains(todayKey)));
  });
}
