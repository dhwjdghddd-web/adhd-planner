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
    expect(find.text('쉬는 날(휴일) 캘린더'), findsOneWidget);
    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);
    expect(find.text('${now.day}'), findsOneWidget);

    // Tap on today's cell to toggle rest day
    await tester.tap(find.text('${now.day}'));
    await tester.pumpAndSettle();

    final restDays = await repo.watchRestDays().first;
    expect(restDays.map((r) => r.dateKey), contains(todayKey));
    expect(find.byIcon(Icons.coffee), findsWidgets);

    // Tap again to untoggle
    await tester.tap(find.text('${now.day}'));
    await tester.pumpAndSettle();

    final restDaysAfter = await repo.watchRestDays().first;
    expect(restDaysAfter.map((r) => r.dateKey), isNot(contains(todayKey)));
  });
}
