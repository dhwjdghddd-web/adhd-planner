import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/onboarding/onboarding_page.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: OnboardingPage()),
    );
  }

  Future<void> goToLastSlide(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('shows the first slide on open', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('구간으로 하루 나누기'), findsOneWidget);
  });

  testWidgets('skip marks onboarding complete without creating segments', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    final segmentsLog = <List<Segment>>[];
    repo.watchSettings().listen(settingsLog.add);
    repo.watchSegments().listen(segmentsLog.add);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.onboardingComplete, true);
    expect(segmentsLog.last, isEmpty);
  });

  testWidgets('paging through reaches the last slide with both finish options', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await goToLastSlide(tester);

    expect(find.text('메모로 잡생각 정리'), findsOneWidget);
    expect(find.text('기본 구간(오전·오후·저녁) 만들고 시작하기'), findsOneWidget);
    expect(find.text('그냥 시작하기'), findsOneWidget);
  });

  testWidgets('"그냥 시작하기" finishes without creating segments', (tester) async {
    final repo = FakePlannerRepository();
    final segmentsLog = <List<Segment>>[];
    repo.watchSegments().listen(segmentsLog.add);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await goToLastSlide(tester);

    await tester.tap(find.text('그냥 시작하기'));
    await tester.pumpAndSettle();

    expect(segmentsLog.last, isEmpty);
  });

  testWidgets('the default-segments button creates 오전/오후/저녁 and finishes', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await goToLastSlide(tester);

    await tester.tap(find.text('기본 구간(오전·오후·저녁) 만들고 시작하기'));
    await tester.pumpAndSettle();

    final segments = await repo.watchSegments().first;
    expect(segments.map((s) => s.name).toSet(), {'오전', '오후', '저녁'});
    expect(settingsLog.last.onboardingComplete, true);
  });
}
