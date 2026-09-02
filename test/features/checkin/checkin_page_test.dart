import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/checkin.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/checkin/checkin_page.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(1080, 2400);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget wrap(FakePlannerRepository repo, {bool autoOpen = false}) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: CheckinPage(autoOpenMoodDialog: autoOpen)),
    );
  }

  testWidgets('renders segmented view buttons (달력, 목록, 통계)', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('달력'), findsOneWidget);
    expect(find.text('목록'), findsOneWidget);
    expect(find.text('통계'), findsOneWidget);
    expect(find.bySemanticsLabel('기분 추가'), findsOneWidget);
  });

  testWidgets('기분 추가 opens dialog and creates a new checkin', (tester) async {
    final repo = FakePlannerRepository();
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('기분 추가'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('기분과 에너지를 기록해요'), findsOneWidget);

    // Save disabled before pick
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed,
      isNull,
    );

    await tester.tap(find.text('😄')); // mood 5
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bolt).at(3)); // energy 4
    await tester.enterText(find.byType(TextField), '오늘 기분 최고!');
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '저장')).onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved.length, 1);
    expect(saved.first.mood, 5);
    expect(saved.first.energy, 4);
    expect(saved.first.note, '오늘 기분 최고!');

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('오늘 기분 최고!'), findsOneWidget);
  });

  testWidgets('can record multiple check-ins in the same day (multi-checkin)', (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    await repo.saveCheckin(
      Checkin.today(
        id: 'c1',
        mood: 4,
        energy: 3,
        note: '오전 체크인',
        at: DateTime(now.year, now.month, now.day, 9, 30),
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오전 체크인'), findsOneWidget);

    // Add second check-in
    await tester.tap(find.bySemanticsLabel('기분 추가'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('🙂'))); // mood 4
    await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.byIcon(Icons.bolt)).at(4)); // energy 5
    await tester.enterText(find.byType(TextField), '오후 활력 체크');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved.length, 2);
    expect(find.text('오전 체크인'), findsOneWidget);
    expect(find.text('오후 활력 체크'), findsOneWidget);
  });

  testWidgets('switching to 목록 view shows grouped timeline with time tags', (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    await repo.saveCheckin(
      Checkin.today(
        id: 'c1',
        mood: 5,
        energy: 4,
        note: '목록 테스트',
        at: DateTime(now.year, now.month, now.day, 14, 15),
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // Switch to 목록
    await tester.tap(find.text('목록'));
    await tester.pumpAndSettle();

    expect(find.text('목록 테스트'), findsOneWidget);
    expect(find.text('기분 5/5'), findsOneWidget);
  });

  testWidgets('switching to 통계 view shows time-of-day cards and weekday chart', (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    await repo.saveCheckin(
      Checkin.today(
        id: 'c1',
        mood: 5,
        energy: 5,
        note: '아침 기록',
        at: DateTime(now.year, now.month, now.day, 8, 30),
      ),
    );
    await repo.saveCheckin(
      Checkin.today(
        id: 'c2',
        mood: 3,
        energy: 2,
        note: '저녁 기록',
        at: DateTime(now.year, now.month, now.day, 19, 0),
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // Switch to 통계
    await tester.tap(find.text('통계'));
    await tester.pumpAndSettle();

    expect(find.text('⏰ 시간대별 기분 & 에너지'), findsOneWidget);
    expect(find.text('🌅 아침 (05~11시)'), findsOneWidget);
    expect(find.text('🌆 저녁 (17~21시)'), findsOneWidget);
    expect(find.text('📅 요일별 평균 패턴'), findsOneWidget);
  });

  testWidgets('editing a checkin updates it in place', (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    await repo.saveCheckin(
      Checkin.today(
        id: 'c1',
        mood: 2,
        energy: 1,
        note: '수정 전 메모',
        at: now,
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('수정 전 메모'), findsOneWidget);

    // Tap the card to edit
    await tester.tap(find.text('수정 전 메모'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '수정하기'), findsOneWidget);

    await tester.tap(find.text('😄')); // change mood to 5
    await tester.enterText(find.byType(TextField), '수정 후 메모');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '수정하기'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved.single.mood, 5);
    expect(saved.single.note, '수정 후 메모');
    expect(find.text('수정 후 메모'), findsOneWidget);
  });

  testWidgets('deleting a checkin via swipe removes it', (tester) async {
    final repo = FakePlannerRepository();
    final now = DateTime.now();
    await repo.saveCheckin(
      Checkin.today(
        id: 'c1',
        mood: 3,
        energy: 3,
        note: '삭제할 메모',
        at: now,
      ),
    );

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('삭제할 메모'), findsOneWidget);

    await tester.drag(find.text('삭제할 메모'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    final saved = await repo.watchCheckins().first;
    expect(saved, isEmpty);
    expect(find.text('삭제할 메모'), findsNothing);
  });

  testWidgets('autoOpenMoodDialog opens dialog on launch', (tester) async {
    final repo = FakePlannerRepository();
    await tester.pumpWidget(wrap(repo, autoOpen: true));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
  });
}
